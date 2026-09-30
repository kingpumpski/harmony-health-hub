-- Close the remaining public SECURITY DEFINER execution boundaries identified by the
-- repository exposure contract. These helpers are either trigger-only internals or
-- server-mediated clinical helpers; clients must not invoke them directly.

ALTER FUNCTION public.enforce_anesthetic_clearance_actor()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.enforce_anesthetic_clearance_actor() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enforce_anesthetic_clearance_actor() FROM anon;
REVOKE EXECUTE ON FUNCTION public.enforce_anesthetic_clearance_actor() FROM authenticated;

ALTER FUNCTION public.record_ai_clinical_event(UUID, TEXT, JSONB)
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.record_ai_clinical_event(UUID, TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_ai_clinical_event(UUID, TEXT, JSONB) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_ai_clinical_event(UUID, TEXT, JSONB) FROM authenticated;

ALTER FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB)
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB) FROM anon;
REVOKE EXECUTE ON FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB) FROM authenticated;

ALTER FUNCTION public.touch_global_hims_updated_at()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.touch_global_hims_updated_at() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.touch_global_hims_updated_at() FROM anon;
REVOKE EXECUTE ON FUNCTION public.touch_global_hims_updated_at() FROM authenticated;

ALTER FUNCTION public.audit_global_hims_change()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.audit_global_hims_change() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.audit_global_hims_change() FROM anon;
REVOKE EXECUTE ON FUNCTION public.audit_global_hims_change() FROM authenticated;

ALTER FUNCTION public.touch_hims_updated_at()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.touch_hims_updated_at() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.touch_hims_updated_at() FROM anon;
REVOKE EXECUTE ON FUNCTION public.touch_hims_updated_at() FROM authenticated;

ALTER FUNCTION public.create_patient_prescription(UUID, TEXT, TEXT, TEXT, TEXT, TEXT)
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.create_patient_prescription(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_patient_prescription(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_patient_prescription(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM authenticated;

ALTER FUNCTION public.current_user_facility_id()
  SET search_path = pg_catalog, public;
REVOKE EXECUTE ON FUNCTION public.current_user_facility_id() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.current_user_facility_id() FROM anon;
REVOKE EXECUTE ON FUNCTION public.current_user_facility_id() FROM authenticated;
