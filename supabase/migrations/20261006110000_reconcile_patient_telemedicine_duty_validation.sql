-- Reconcile patient telemedicine requests with the clinician duty roster.
-- Patient requests remain self-service and never grant clinical workflow access.

BEGIN;

CREATE OR REPLACE FUNCTION public.request_patient_telemedicine_session(
  _clinician_id uuid,
  _scheduled_at timestamptz,
  _reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_patient uuid;
  v_facility uuid;
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.has_role(v_uid,'patient') THEN
    RAISE EXCEPTION 'Patient telemedicine access is not permitted';
  END IF;

  SELECT p.id,p.facility_id INTO v_patient,v_facility
  FROM public.patients p
  WHERE (p.user_id=v_uid OR (p.user_id IS NULL AND lower(p.email)=lower(auth.jwt()->>'email')))
    AND coalesce(p.status,'active')<>'inactive'
  ORDER BY (p.user_id=v_uid) DESC,p.created_at DESC
  LIMIT 1;

  IF v_patient IS NULL OR v_facility IS NULL THEN
    RAISE EXCEPTION 'Patient profile or facility is not configured';
  END IF;
  IF _scheduled_at IS NULL OR _scheduled_at<=now() THEN
    RAISE EXCEPTION 'Choose a future date and time';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles p
    JOIN public.user_roles ur ON ur.user_id=p.id
    JOIN public.facility_memberships fm ON fm.user_id=p.id AND fm.is_active=true AND fm.facility_id=v_facility
    WHERE p.id=_clinician_id
      AND ur.role IN ('practitioner'::public.app_role,'radiologist'::public.app_role)
      AND EXISTS (
        SELECT 1
        FROM public.staff_shift_assignments s
        WHERE s.user_id=p.id
          AND s.active=true
          AND s.starts_at<=_scheduled_at
          AND s.ends_at>_scheduled_at
      )
  ) THEN
    RAISE EXCEPTION 'Selected clinician is not on duty at the requested date and time';
  END IF;

  INSERT INTO public.video_sessions(
    patient_id,practitioner_id,room_name,provider,scheduled_at,status,
    payment_required,payment_received,notes,facility_id
  )
  VALUES(
    v_patient,_clinician_id,
    'pending-'||replace(gen_random_uuid()::text,'-',''),
    'jitsi',_scheduled_at,'pending_approval',
    false,false,nullif(trim(_reason),''),
    v_facility
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.request_patient_telemedicine_session(uuid,timestamptz,text) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.request_patient_telemedicine_session(uuid,timestamptz,text) TO authenticated;

NOTIFY pgrst,'reload schema';

COMMIT;
