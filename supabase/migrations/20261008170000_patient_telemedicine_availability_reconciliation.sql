-- Reconcile patient telemedicine clinician discovery with scheduled-time availability.
-- Shift-aware when staff shift data exists; keeps UAT usable before shifts are configured.

BEGIN;

DROP FUNCTION IF EXISTS public.get_patient_telemedicine_clinicians(timestamptz);

CREATE FUNCTION public.get_patient_telemedicine_clinicians(
  _scheduled_at timestamptz DEFAULT null
)
RETURNS TABLE(
  id uuid,
  first_name text,
  last_name text,
  department text,
  specialization text,
  clinician_role text,
  is_on_duty boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_facility uuid;
  v_at timestamptz := coalesce(_scheduled_at, now() + interval '1 day');
  v_has_shift_data boolean;
BEGIN
  IF v_uid IS NULL OR NOT public.has_role(v_uid, 'patient') THEN
    RAISE EXCEPTION 'Patient telemedicine access is not permitted';
  END IF;
  IF v_at <= now() THEN
    RAISE EXCEPTION 'Choose a future date and time';
  END IF;

  SELECT p.facility_id INTO v_facility
  FROM public.patients p
  WHERE (p.user_id = v_uid OR (p.user_id IS NULL AND lower(p.email) = lower((auth.jwt() ->> 'email'))))
    AND coalesce(p.status, 'active') <> 'inactive'
  ORDER BY (p.user_id = v_uid) DESC, p.created_at DESC
  LIMIT 1;

  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility is not configured';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.staff_shift_assignments s
    JOIN public.facility_memberships fm
      ON fm.user_id = s.user_id
     AND fm.facility_id = v_facility
     AND fm.is_active = true
    WHERE s.active = true
  ) INTO v_has_shift_data;

  RETURN QUERY
  SELECT DISTINCT
    p.id,
    p.first_name,
    p.last_name,
    p.department,
    p.specialization,
    ur.role::text,
    CASE
      WHEN NOT v_has_shift_data THEN true
      ELSE EXISTS (
        SELECT 1 FROM public.staff_shift_assignments s
        WHERE s.user_id = p.id
          AND s.active = true
          AND s.starts_at <= v_at
          AND s.ends_at > v_at
      )
    END
  FROM public.profiles p
  JOIN public.user_roles ur ON ur.user_id = p.id
  JOIN public.facility_memberships fm
    ON fm.user_id = p.id
   AND fm.is_active = true
   AND fm.facility_id = v_facility
  WHERE ur.role IN ('practitioner'::public.app_role, 'radiologist'::public.app_role)
    AND (
      NOT v_has_shift_data
      OR EXISTS (
        SELECT 1 FROM public.staff_shift_assignments s
        WHERE s.user_id = p.id
          AND s.active = true
          AND s.starts_at <= v_at
          AND s.ends_at > v_at
      )
    )
  ORDER BY p.last_name, p.first_name;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_patient_telemedicine_clinicians(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_telemedicine_clinicians(timestamptz) TO authenticated;

COMMIT;