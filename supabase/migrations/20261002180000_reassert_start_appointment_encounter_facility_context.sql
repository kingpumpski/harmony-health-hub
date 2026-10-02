-- Reassert the hardened encounter-start RPC after live diagnostics showed
-- the deployed function still reaching assign_active_facility() and failing
-- late with Facility context mismatch. This migration is deliberately newer
-- than the existing test-facility context migration.
BEGIN;

CREATE OR REPLACE FUNCTION public.start_appointment_encounter(
  _appointment_id uuid,
  _symptoms text DEFAULT NULL,
  _clerking_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_is_privileged boolean := public.has_role(v_user, 'admin'::public.app_role)
    OR public.has_role(v_user, 'it_admin'::public.app_role);
  v_appt public.appointments;
  v_patient_facility uuid;
  v_encounter public.encounters;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    v_is_privileged
    OR public.has_role(v_user, 'practitioner'::public.app_role)
    OR public.has_role(v_user, 'nurse'::public.app_role)
    OR public.has_role(v_user, 'midwife'::public.app_role)
    OR public.has_role(v_user, 'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Clinical access required';
  END IF;

  SELECT * INTO v_appt FROM public.appointments
  WHERE id = _appointment_id FOR UPDATE;

  IF v_appt.id IS NULL THEN
    RAISE EXCEPTION 'Appointment not found';
  END IF;

  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p
  WHERE p.id = v_appt.patient_id FOR UPDATE;

  IF v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved; reconcile the patient before starting the appointment';
  END IF;

  IF public.hms_current_user_is_test_user()
     AND v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN
    RAISE EXCEPTION 'Test mode is active. Test accounts can start encounters only for patients in the Harmony Health Hub Test Facility. Use a test-facility patient or ask the system super admin to disable test mode before working with this facility.';
  END IF;

  -- Validate against the same resolver used by the INSERT trigger before any
  -- appointment mutation, so context failures are actionable and atomic.
  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'An active facility is required before starting an appointment encounter';
  END IF;

  IF v_patient_facility IS DISTINCT FROM v_facility THEN
    RAISE EXCEPTION 'Facility context mismatch. Select the patient facility before starting the encounter';
  END IF;

  IF v_appt.facility_id IS NOT NULL
     AND v_appt.facility_id IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION 'Appointment belongs to a different facility context';
  END IF;

  IF v_appt.facility_id IS NULL THEN
    UPDATE public.appointments SET facility_id = v_patient_facility, updated_at = pg_catalog.now()
    WHERE id = v_appt.id AND facility_id IS NULL;
    SELECT * INTO v_appt FROM public.appointments WHERE id = _appointment_id FOR UPDATE;
  END IF;

  IF v_appt.facility_id IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION 'Appointment belongs to a different facility context';
  END IF;

  IF v_appt.treatment_status IN ('completed', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'Appointment is not available for treatment';
  END IF;

  IF v_appt.attending_officer_id IS NOT NULL
     AND v_appt.attending_officer_id <> v_user AND NOT v_is_privileged THEN
    RAISE EXCEPTION 'Appointment is assigned to another officer';
  END IF;

  UPDATE public.appointments
  SET attending_officer_id = v_user,
      claimed_at = COALESCE(claimed_at, pg_catalog.now()),
      treatment_status = 'in_progress',
      started_at = COALESCE(started_at, pg_catalog.now()),
      updated_at = pg_catalog.now()
  WHERE id = _appointment_id;

  SELECT e.* INTO v_encounter FROM public.encounters e
  WHERE e.appointment_id = _appointment_id
  ORDER BY e.created_at DESC LIMIT 1 FOR UPDATE;

  IF v_encounter.id IS NULL THEN
    INSERT INTO public.encounters (
      patient_id, appointment_id, practitioner_id, encounter_type,
      symptoms, clerking_notes, status, facility_id
    ) VALUES (
      v_appt.patient_id, _appointment_id, v_user, 'consultation',
      NULLIF(pg_catalog.btrim(_symptoms), ''),
      NULLIF(pg_catalog.btrim(_clerking_notes), ''),
      'in_progress', v_patient_facility
    ) RETURNING * INTO v_encounter;
  ELSE
    IF v_encounter.patient_id IS DISTINCT FROM v_appt.patient_id THEN
      RAISE EXCEPTION 'Encounter patient does not match appointment patient';
    END IF;
    IF v_encounter.facility_id IS NULL THEN
      UPDATE public.encounters SET facility_id = v_patient_facility, updated_at = pg_catalog.now()
      WHERE id = v_encounter.id RETURNING * INTO v_encounter;
    END IF;
    IF v_encounter.facility_id IS DISTINCT FROM v_patient_facility THEN
      RAISE EXCEPTION 'Encounter belongs to a different facility context';
    END IF;
    UPDATE public.encounters
    SET practitioner_id = COALESCE(practitioner_id, v_user),
        symptoms = COALESCE(NULLIF(pg_catalog.btrim(_symptoms), ''), symptoms),
        clerking_notes = COALESCE(NULLIF(pg_catalog.btrim(_clerking_notes), ''), clerking_notes),
        status = CASE WHEN status = 'draft' THEN 'in_progress' ELSE status END,
        updated_at = pg_catalog.now()
    WHERE id = v_encounter.id RETURNING * INTO v_encounter;
  END IF;

  RETURN v_encounter.id;
END;
$function$;

REVOKE ALL ON FUNCTION public.start_appointment_encounter(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(uuid,text,text) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
