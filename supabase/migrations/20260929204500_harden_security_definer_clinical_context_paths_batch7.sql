-- Batch 7: harden high-impact patient/clinical/medication SECURITY DEFINER paths.
-- Search-path hardening only; signatures and authorization behavior are preserved.
ALTER FUNCTION public.get_ai_clinical_context(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_encounter_workflow_workspace() SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_patient_appointments(uuid, integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_patient_bmi_context(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.patient_coverage_details(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.record_patient_deposit(uuid, numeric, text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.save_encounter_draft(uuid, text, text, text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.schedule_medication_administration(uuid, text, text, text, timestamptz, text, integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.search_patient_directory(text, integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.start_appointment_encounter(uuid, text, text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.transition_medication_administration(uuid, text, text, text, uuid) SET search_path = pg_catalog, public;
