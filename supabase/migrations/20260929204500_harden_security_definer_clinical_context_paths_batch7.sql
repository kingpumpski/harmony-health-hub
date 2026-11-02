-- Batch 7: harden high-impact patient/clinical/medication SECURITY DEFINER paths.
-- Search-path hardening only; signatures and authorization behavior are preserved.
ALTER FUNCTION public.get_ai_clinical_context(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_encounter_workflow_workspace() SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_patient_appointments(uuid, integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_patient_bmi_context(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.patient_coverage_details(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.record_patient_deposit(uuid, numeric, text) SET search_path = pg_catalog, public;
-- The local replay chain creates save_encounter_draft in a later
-- encounter-facility migration. Production may already have the helper from
-- its canonical baseline. Skip if absent, and preserve an already-empty path.
DO $batch7_encounter_draft$
DECLARE
  v_function regprocedure := to_regprocedure('public.save_encounter_draft(uuid, text, text, text)');
  v_config text[];
BEGIN
  IF v_function IS NOT NULL THEN
    SELECT p.proconfig INTO v_config
    FROM pg_catalog.pg_proc p
    WHERE p.oid = v_function;

    IF NOT COALESCE(v_config @> ARRAY['search_path=""'], false) THEN
      EXECUTE 'ALTER FUNCTION public.save_encounter_draft(uuid, text, text, text) SET search_path = pg_catalog, public';
    END IF;
  END IF;
END;
$batch7_encounter_draft$;
ALTER FUNCTION public.schedule_medication_administration(uuid, text, text, text, timestamptz, text, integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.search_patient_directory(text, integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.start_appointment_encounter(uuid, text, text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.transition_medication_administration(uuid, text, text, text, uuid) SET search_path = pg_catalog, public;
