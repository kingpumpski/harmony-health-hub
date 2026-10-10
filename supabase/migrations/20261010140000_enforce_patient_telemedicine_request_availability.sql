-- Enforce telemedicine request validity at the database boundary.
-- Patient UI checks are usability aids; this function remains the authority for
-- facility, clinician-role, schedule, shift, and reason validation.
BEGIN;

CREATE OR REPLACE FUNCTION public.request_patient_telemedicine_session(
  _clinician_id uuid,
  _scheduled_at timestamptz,
  _reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_patient uuid;
  v_facility uuid;
  v_session_id uuid;
  v_has_shift_data boolean;
BEGIN
  IF v_uid IS NULL OR NOT public.has_role(v_uid, 'patient') THEN
    RAISE EXCEPTION 'Patient telemedicine access is not permitted';
  END IF;

  IF _scheduled_at IS NULL OR _scheduled_at <= now() THEN
    RAISE EXCEPTION 'Choose a future date and time';
  END IF;
  IF nullif(trim(_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A reason for the visit is required';
  END IF;
  IF length(trim(_reason)) > 2000 THEN
    RAISE EXCEPTION 'The reason for the visit must be 2000 characters or fewer';
  END IF;
  IF _clinician_id IS NULL THEN
    RAISE EXCEPTION 'Select an available clinician';
  END IF;

  SELECT p.id, p.facility_id
  INTO v_patient, v_facility
  FROM public.patients p
  WHERE (p.user_id = v_uid OR (
    p.user_id IS NULL
    AND lower(p.email) = lower((auth.jwt() ->> 'email'))
  ))
    AND coalesce(p.status, 'active') <> 'inactive'
  ORDER BY (p.user_id = v_uid) DESC, p.created_at DESC
  LIMIT 1;

  IF v_patient IS NULL OR v_facility IS NULL THEN
    RAISE EXCEPTION 'Patient profile or facility is not configured';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles p
    JOIN public.user_roles ur ON ur.user_id = p.id
    JOIN public.facility_memberships fm
      ON fm.user_id = p.id
     AND fm.facility_id = v_facility
     AND fm.is_active = true
    WHERE p.id = _clinician_id
      AND ur.role IN ('practitioner'::public.app_role, 'radiologist'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Selected clinician is not available at this facility';
  END IF;

  -- If this facility uses shift assignments, revalidate the selected clinician
  -- against the requested timestamp to prevent stale or forged availability.
  SELECT EXISTS (
    SELECT 1
    FROM public.staff_shift_assignments s
    JOIN public.facility_memberships fm
      ON fm.user_id = s.user_id
     AND fm.facility_id = v_facility
     AND fm.is_active = true
    WHERE s.active = true
  ) INTO v_has_shift_data;

  IF v_has_shift_data AND NOT EXISTS (
    SELECT 1
    FROM public.staff_shift_assignments s
    JOIN public.facility_memberships fm
      ON fm.user_id = s.user_id
     AND fm.facility_id = v_facility
     AND fm.is_active = true
    WHERE s.user_id = _clinician_id
      AND s.active = true
      AND s.starts_at <= _scheduled_at
      AND s.ends_at > _scheduled_at
  ) THEN
    RAISE EXCEPTION 'Selected clinician is not on duty at the requested time';
  END IF;

  INSERT INTO public.video_sessions(
    patient_id, practitioner_id, room_name, provider, scheduled_at, status,
    payment_required, payment_received, notes, facility_id
  )
  VALUES (
    v_patient,
    _clinician_id,
    'pending-' || replace(gen_random_uuid()::text, '-', ''),
    'jitsi',
    _scheduled_at,
    'pending_approval',
    false,
    false,
    nullif(trim(_reason), ''),
    v_facility
  )
  RETURNING id INTO v_session_id;

  RETURN v_session_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.request_patient_telemedicine_session(uuid,timestamptz,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_patient_telemedicine_session(uuid,timestamptz,text) TO authenticated;
NOTIFY pgrst, 'reload schema';

COMMIT;
