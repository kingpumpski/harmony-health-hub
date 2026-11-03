-- Batch 6: harden SECURITY DEFINER read/workspace function search paths.
-- No signatures, role gates, query projections, or workflow behavior are changed.

ALTER FUNCTION public.get_admission_workspace(integer)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_appointment_worklist(integer)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_attending_patient_history(uuid, uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_department_queue(text, integer)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_emergency_workspace(integer)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_encounter_clinical_context(uuid, uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_imaging_workspace(integer)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_laboratory_workspace(integer)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_maternity_workspace(integer, uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_patient_admission_history(uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_patient_directory_record(uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_patient_hub_clinical_snapshot(uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_patient_invoices(uuid, integer)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.get_pharmacy_workspace(integer)
  SET search_path = pg_catalog, public;
