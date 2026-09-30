-- Harden internal SECURITY DEFINER trigger helpers against direct Data API execution.
--
-- These functions are PostgreSQL trigger entry points, not application RPCs.
-- Keep their privileged execution path safe while removing client execution
-- exposure explicitly and deterministically.

ALTER FUNCTION public.validate_ai_clinical_session_state()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.validate_ai_clinical_session_state() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_ai_clinical_session_state() FROM anon;
REVOKE EXECUTE ON FUNCTION public.validate_ai_clinical_session_state() FROM authenticated;

ALTER FUNCTION public.set_anesthetic_assessment_actor()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.set_anesthetic_assessment_actor() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_anesthetic_assessment_actor() FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_anesthetic_assessment_actor() FROM authenticated;

ALTER FUNCTION public.set_anesthetic_assessor()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.set_anesthetic_assessor() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_anesthetic_assessor() FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_anesthetic_assessor() FROM authenticated;

ALTER FUNCTION public.validate_service_order_transition()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.validate_service_order_transition() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_service_order_transition() FROM anon;
REVOKE EXECUTE ON FUNCTION public.validate_service_order_transition() FROM authenticated;

ALTER FUNCTION public.validate_service_order_insert()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.validate_service_order_insert() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_service_order_insert() FROM anon;
REVOKE EXECUTE ON FUNCTION public.validate_service_order_insert() FROM authenticated;

ALTER FUNCTION public.enforce_service_payment_gate()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.enforce_service_payment_gate() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enforce_service_payment_gate() FROM anon;
REVOKE EXECUTE ON FUNCTION public.enforce_service_payment_gate() FROM authenticated;

ALTER FUNCTION public.set_patient_documents_updated_at()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.set_patient_documents_updated_at() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_patient_documents_updated_at() FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_patient_documents_updated_at() FROM authenticated;

ALTER FUNCTION public.audit_patient_change()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.audit_patient_change() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.audit_patient_change() FROM anon;
REVOKE EXECUTE ON FUNCTION public.audit_patient_change() FROM authenticated;

ALTER FUNCTION public.audit_patient_changes()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.audit_patient_changes() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.audit_patient_changes() FROM anon;
REVOKE EXECUTE ON FUNCTION public.audit_patient_changes() FROM authenticated;

ALTER FUNCTION public.touch_ai_clinical_session()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.touch_ai_clinical_session() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.touch_ai_clinical_session() FROM anon;
REVOKE EXECUTE ON FUNCTION public.touch_ai_clinical_session() FROM authenticated;

ALTER FUNCTION public.notify_financial_settlement_event()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.notify_financial_settlement_event() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_financial_settlement_event() FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_financial_settlement_event() FROM authenticated;

ALTER FUNCTION public.suppress_duplicate_gated_source_invoice_item()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.suppress_duplicate_gated_source_invoice_item() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.suppress_duplicate_gated_source_invoice_item() FROM anon;
REVOKE EXECUTE ON FUNCTION public.suppress_duplicate_gated_source_invoice_item() FROM authenticated;
