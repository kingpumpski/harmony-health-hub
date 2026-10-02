BEGIN;

-- Gate A: appointment claiming must preserve the same facility/test-mode boundary
-- as encounter creation. Privileged roles do not bypass TEST-0001 isolation.
CREATE OR REPLACE FUNCTION public.claim_appointment(_appointment_id uuid)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  result public.appointments;
  v_patient_facility uuid;
  v_is_privileged boolean := public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role);
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    v_is_privileged
    OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role)
    OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Only attending clinical officers may claim appointments';
  END IF;

  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'An active facility is required';
  END IF;

  SELECT * INTO result
  FROM public.appointments
  WHERE id = _appointment_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found'; END IF;

  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p
  WHERE p.id = result.patient_id
  FOR SHARE;
  IF v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved';
  END IF;

  -- Test-mode isolation is evaluated before privileged-role exceptions.
  IF public.hms_current_user_is_test_user()
     AND v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN
    RAISE EXCEPTION 'Test mode is active. Test accounts can claim appointments only for patients in the Harmony Health Hub Test Facility. Use a test-facility patient or ask the system super admin to disable test mode before working with this facility.';
  END IF;

  IF v_patient_facility IS DISTINCT FROM v_facility THEN
    RAISE EXCEPTION 'Appointment or patient belongs to a different facility context';
  END IF;

  IF result.facility_id IS NOT NULL
     AND result.facility_id IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION 'Appointment belongs to a different facility context';
  END IF;

  IF result.attending_officer_id IS NOT NULL
     AND result.attending_officer_id <> uid
     AND NOT v_is_privileged THEN
    RAISE EXCEPTION 'Appointment is already assigned to another officer';
  END IF;

  UPDATE public.appointments
  SET attending_officer_id = uid,
      claimed_at = COALESCE(claimed_at, pg_catalog.now()),
      treatment_status = CASE WHEN treatment_status = 'scheduled' THEN 'claimed' ELSE treatment_status END,
      updated_at = pg_catalog.now()
  WHERE id = result.id
  RETURNING * INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_appointment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_appointment(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
