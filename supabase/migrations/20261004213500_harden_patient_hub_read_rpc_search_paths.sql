BEGIN;

ALTER FUNCTION public.get_patient_appointments(uuid, integer) SET search_path = '';
ALTER FUNCTION public.get_patient_admission_history(uuid) SET search_path = '';
ALTER FUNCTION public.get_patient_hub_clinical_snapshot(uuid) SET search_path = '';

REVOKE ALL ON FUNCTION public.get_patient_appointments(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_patient_appointments(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_patient_appointments(uuid, integer) TO authenticated;

REVOKE ALL ON FUNCTION public.get_patient_admission_history(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_patient_admission_history(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_patient_admission_history(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.get_patient_hub_clinical_snapshot(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_patient_hub_clinical_snapshot(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_patient_hub_clinical_snapshot(uuid) TO authenticated;

COMMIT;