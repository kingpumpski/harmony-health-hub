-- Pin patient-journey SECURITY DEFINER wrappers to an empty search path.
-- Function bodies use schema-qualified application objects and pg_catalog-safe built-ins.

ALTER FUNCTION public.activate_patient_visit_coverage(uuid,text,uuid,date) SET search_path = '';
ALTER FUNCTION public.create_patient_document(uuid,text,text,text) SET search_path = '';
ALTER FUNCTION public.create_patient_referral_workflow(uuid,text,text,text,text,text) SET search_path = '';

REVOKE ALL ON FUNCTION public.activate_patient_visit_coverage(uuid,text,uuid,date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_patient_visit_coverage(uuid,text,uuid,date) FROM anon;
GRANT EXECUTE ON FUNCTION public.activate_patient_visit_coverage(uuid,text,uuid,date) TO authenticated;

REVOKE ALL ON FUNCTION public.create_patient_document(uuid,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_patient_document(uuid,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_patient_document(uuid,text,text,text) TO authenticated;

REVOKE ALL ON FUNCTION public.create_patient_referral_workflow(uuid,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_patient_referral_workflow(uuid,text,text,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_patient_referral_workflow(uuid,text,text,text,text,text) TO authenticated;
