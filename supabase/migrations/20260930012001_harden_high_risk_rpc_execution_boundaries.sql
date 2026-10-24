-- Reconcile explicit execution boundaries and SECURITY DEFINER search paths for the
-- selected high-risk patient-scoped application RPCs.
--
-- This migration does NOT enable patient/facility tenancy. Those workflows remain
-- classified as pending until isolated two-facility regression evidence exists.

ALTER FUNCTION public.create_ai_clinical_session(uuid,text,jsonb,jsonb)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_insurance_claim_draft(uuid,text,text,numeric,uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.update_patient_workflow(uuid,jsonb)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.search_patient_directory(text,integer)
  SET search_path = pg_catalog, public;

REVOKE ALL ON FUNCTION public.create_ai_clinical_session(uuid,text,jsonb,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_ai_clinical_session(uuid,text,jsonb,jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) TO authenticated;

REVOKE ALL ON FUNCTION public.create_insurance_claim_draft(uuid,text,text,numeric,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_insurance_claim_draft(uuid,text,text,numeric,uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.update_patient_workflow(uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_patient_workflow(uuid,jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) TO authenticated;

REVOKE ALL ON FUNCTION public.search_patient_directory(text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_patient_directory(text,integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
