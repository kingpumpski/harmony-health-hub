-- Final effective-state hardening for the legacy Patient Hub entrypoints.
-- Keep this explicit ALTER layer so repository audits and the live database
-- both resolve these SECURITY DEFINER functions to an empty search_path.
ALTER FUNCTION public.create_patient_appointment(UUID, TIMESTAMPTZ, TEXT, TEXT) SET search_path = '';
ALTER FUNCTION public.record_patient_vitals(UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) SET search_path = '';
ALTER FUNCTION public.create_patient_lab_order(UUID, TEXT, TEXT) SET search_path = '';
ALTER FUNCTION public.create_patient_document(UUID, TEXT, TEXT, TEXT) SET search_path = '';
ALTER FUNCTION public.create_patient_admission(UUID, TEXT, TEXT, UUID) SET search_path = '';
