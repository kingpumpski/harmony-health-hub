-- Gate A: harden shared encounter facility attribution and diagnosis write path.
CREATE OR REPLACE FUNCTION public.ensure_encounter_facility_attribution(_encounter_id uuid)
RETURNS public.encounters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid;
  v_enc public.encounters;
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Not authorized to establish encounter facility context'; END IF;

  SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF v_enc.id IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;

  SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=v_enc.patient_id FOR UPDATE;
  IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved; reconcile the patient before clinical documentation'; END IF;
  IF v_enc.facility_id IS NULL THEN
    -- Attribution is allowed only to the patient facility after all boundary checks.
    NULL;
  END IF;

  IF public.hms_test_mode_enabled() THEN
    IF v_patient_facility IS DISTINCT FROM public.hms_test_facility_id()
       OR (v_enc.facility_id IS NOT NULL AND v_enc.facility_id IS DISTINCT FROM public.hms_test_facility_id()) THEN
      RAISE EXCEPTION 'Test mode permits clinical documentation only within TEST-0001';
    END IF;
    v_facility := public.hms_test_facility_id();
  ELSE
    v_facility := public.current_user_facility_id();
    IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before continuing clinical documentation'; END IF;
    IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin'))
       AND v_patient_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Patient belongs to a different facility context';
    END IF;
    IF v_enc.facility_id IS NOT NULL AND v_enc.facility_id IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Encounter belongs to a different facility context';
    END IF;
  END IF;

  IF v_enc.facility_id IS NULL THEN
    UPDATE public.encounters SET facility_id=v_patient_facility, updated_at=pg_catalog.now()
    WHERE id=v_enc.id RETURNING * INTO v_enc;
  END IF;
  RETURN v_enc;
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_encounter_diagnosis(
  _encounter_id uuid, _diagnosis text, _icd_code text DEFAULT NULL
)
RETURNS public.diagnoses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  result public.diagnoses;
  normalized_code text := NULLIF(pg_catalog.upper(pg_catalog.btrim(_icd_code)),'');
  v_enc public.encounters;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Not authorized to add diagnoses'; END IF;

  v_enc := public.ensure_encounter_facility_attribution(_encounter_id);
  IF v_enc.status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
  IF NULLIF(pg_catalog.btrim(_diagnosis),'') IS NULL THEN RAISE EXCEPTION 'Diagnosis is required'; END IF;
  IF normalized_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.icd_codes WHERE code=normalized_code) THEN
    RAISE EXCEPTION 'Diagnosis code is not in the approved ICD-10/STG catalogue';
  END IF;

  INSERT INTO public.diagnoses(encounter_id,diagnosis,icd_code,is_principal,facility_id)
  VALUES(_encounter_id,pg_catalog.btrim(_diagnosis),normalized_code,false,v_enc.facility_id)
  RETURNING * INTO result;
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.ensure_encounter_facility_attribution(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_encounter_facility_attribution(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.add_encounter_diagnosis(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_encounter_diagnosis(uuid,text,text) TO authenticated;
NOTIFY pgrst, 'reload schema';