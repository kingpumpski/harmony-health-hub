BEGIN;

-- Test-mode users are deliberately bound to the dedicated TEST-0001 facility.
-- Never allow an admin's cross-facility read privileges to bypass the facility
-- boundary on appointment/encounter writes. This also prevents a late trigger
-- failure after the appointment row has already been updated in the function.

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

  SELECT * INTO v_appt
  FROM public.appointments
  WHERE id = _appointment_id
  FOR UPDATE;

  IF v_appt.id IS NULL THEN
    RAISE EXCEPTION 'Appointment not found';
  END IF;

  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p
  WHERE p.id = v_appt.patient_id
  FOR UPDATE;

  IF v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved; reconcile the patient before starting the appointment';
  END IF;

  IF public.hms_current_user_is_test_user()
     AND v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN
    RAISE EXCEPTION 'Test mode is active. Test accounts can start encounters only for patients in the Harmony Health Hub Test Facility. Use a test-facility patient or ask the system super admin to disable test mode before working with this facility.';
  END IF;

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
    UPDATE public.appointments
    SET facility_id = v_patient_facility, updated_at = pg_catalog.now()
    WHERE id = v_appt.id AND facility_id IS NULL;
    SELECT * INTO v_appt
    FROM public.appointments
    WHERE id = _appointment_id
    FOR UPDATE;
  END IF;

  IF v_appt.facility_id IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION 'Appointment belongs to a different facility context';
  END IF;

  IF v_appt.treatment_status IN ('completed', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'Appointment is not available for treatment';
  END IF;

  IF v_appt.attending_officer_id IS NOT NULL
     AND v_appt.attending_officer_id <> v_user
     AND NOT v_is_privileged THEN
    RAISE EXCEPTION 'Appointment is assigned to another officer';
  END IF;

  UPDATE public.appointments
  SET attending_officer_id = v_user,
      claimed_at = COALESCE(claimed_at, pg_catalog.now()),
      treatment_status = 'in_progress',
      started_at = COALESCE(started_at, pg_catalog.now()),
      updated_at = pg_catalog.now()
  WHERE id = _appointment_id;

  SELECT e.* INTO v_encounter
  FROM public.encounters e
  WHERE e.appointment_id = _appointment_id
  ORDER BY e.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_encounter.id IS NULL THEN
    INSERT INTO public.encounters (
      patient_id, appointment_id, practitioner_id, encounter_type,
      symptoms, clerking_notes, status, facility_id
    ) VALUES (
      v_appt.patient_id, _appointment_id, v_user, 'consultation',
      NULLIF(pg_catalog.btrim(_symptoms), ''),
      NULLIF(pg_catalog.btrim(_clerking_notes), ''),
      'in_progress', v_patient_facility
    )
    RETURNING * INTO v_encounter;
  ELSE
    IF v_encounter.patient_id IS DISTINCT FROM v_appt.patient_id THEN
      RAISE EXCEPTION 'Encounter patient does not match appointment patient';
    END IF;
    IF v_encounter.facility_id IS NULL THEN
      UPDATE public.encounters
      SET facility_id = v_patient_facility, updated_at = pg_catalog.now()
      WHERE id = v_encounter.id
      RETURNING * INTO v_encounter;
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
    WHERE id = v_encounter.id
    RETURNING * INTO v_encounter;
  END IF;

  RETURN v_encounter.id;
END;
$function$;

REVOKE ALL ON FUNCTION public.start_appointment_encounter(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(uuid,text,text) TO authenticated;

-- Align Patient Hub profile access with the same non-locking facility assertion
-- used by the other read-only Patient Hub RPCs. Admin/IT admin can inspect a
-- patient across facilities, while other roles remain restricted to their
-- active facility. Unattributed/inactive records return an actionable error
-- instead of being silently presented as "not found".

CREATE OR REPLACE FUNCTION public.get_patient_profile_for_user(_patient_id uuid)
RETURNS TABLE (
  id uuid,
  patient_code text,
  first_name text,
  last_name text,
  date_of_birth date,
  gender text,
  email text,
  phone text,
  address text,
  city text,
  ghana_card_number text,
  blood_group text,
  genotype text,
  allergies text,
  chronic_conditions text,
  insurance_provider text,
  insurance_number text,
  insurance_group_number text,
  insurance_expiry date,
  insurance_company_id uuid,
  emergency_contact_name text,
  emergency_contact_phone text,
  emergency_contact_relation text,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid, 'admin'::public.app_role)
    OR public.has_role(uid, 'it_admin'::public.app_role)
    OR public.has_role(uid, 'practitioner'::public.app_role)
    OR public.has_role(uid, 'nurse'::public.app_role)
    OR public.has_role(uid, 'midwife'::public.app_role)
    OR public.has_role(uid, 'specialist_nurse'::public.app_role)
    OR public.has_role(uid, 'lab_technician'::public.app_role)
    OR public.has_role(uid, 'radiologist'::public.app_role)
    OR public.has_role(uid, 'radiology_technician'::public.app_role)
    OR public.has_role(uid, 'pharmacist'::public.app_role)
    OR public.has_role(uid, 'accountant'::public.app_role)
    OR public.has_role(uid, 'front_desk'::public.app_role)
    OR public.has_role(uid, 'canteen'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Not authorized to access the patient record';
  END IF;

  PERFORM public.assert_patient_facility_read_context(_patient_id);

  RETURN QUERY
  SELECT
    p.id,
    p.patient_code,
    p.first_name,
    p.last_name,
    p.date_of_birth,
    p.gender::text,
    p.email,
    p.phone,
    p.address,
    p.city,
    p.ghana_card_number,
    p.blood_group::text,
    p.genotype::text,
    p.allergies,
    p.chronic_conditions,
    p.insurance_provider,
    p.insurance_number,
    p.insurance_group_number,
    p.insurance_expiry,
    p.insurance_company_id,
    p.emergency_contact_name,
    p.emergency_contact_phone,
    p.emergency_contact_relation,
    p.status::text
  FROM public.patients p
  WHERE p.id = _patient_id
    AND coalesce(p.status, 'active') <> 'inactive';
END;
$function$;

REVOKE ALL ON FUNCTION public.get_patient_profile_for_user(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_profile_for_user(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
