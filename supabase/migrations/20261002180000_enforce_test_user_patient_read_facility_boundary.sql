-- Test-mode isolation must apply to reads as well as writes.
-- Administrator privileges do not allow a test account to read production-facility
-- patient history while its effective facility is TEST-0001.
CREATE OR REPLACE FUNCTION public.assert_patient_facility_read_context(_patient_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  patient_facility uuid;
  active_facility uuid := public.current_user_facility_id();
  test_facility uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF _patient_id IS NULL THEN
    RAISE EXCEPTION 'Patient is required';
  END IF;

  SELECT p.facility_id
    INTO patient_facility
  FROM public.patients p
  WHERE p.id = _patient_id
    AND coalesce(p.status, 'active') <> 'inactive';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Patient not found or inactive';
  END IF;

  IF patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved';
  END IF;

  -- Enforce the test boundary before any administrator cross-facility read
  -- exception. Test accounts are restricted to the dedicated test facility.
  IF public.hms_current_user_is_test_user() THEN
    test_facility := public.hms_test_facility_id();

    IF test_facility IS NULL THEN
      RAISE EXCEPTION 'Test mode is active but the TEST-0001 facility is not configured';
    END IF;

    IF patient_facility IS DISTINCT FROM test_facility THEN
      RAISE EXCEPTION 'Test mode is active. Test accounts can access patient records only in the Harmony Health Hub Test Facility (TEST-0001).';
    END IF;

    RETURN patient_facility;
  END IF;

  IF public.has_role(uid, 'admin'::public.app_role)
     OR public.has_role(uid, 'it_admin'::public.app_role) THEN
    RETURN patient_facility;
  END IF;

  IF active_facility IS NULL THEN
    RAISE EXCEPTION 'Active facility context is required';
  END IF;

  IF patient_facility IS DISTINCT FROM active_facility THEN
    RAISE EXCEPTION 'Patient belongs to a different facility context';
  END IF;

  RETURN patient_facility;
END;
$function$;

-- This is an internal authorization helper; clients call the approved patient
-- history RPCs, which invoke this function under their definer privileges.
REVOKE ALL ON FUNCTION public.assert_patient_facility_read_context(uuid) FROM PUBLIC, anon, authenticated;
NOTIFY pgrst, 'reload schema';
