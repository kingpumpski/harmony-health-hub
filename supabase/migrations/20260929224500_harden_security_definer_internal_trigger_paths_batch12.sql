-- Batch 12: harden internal/trigger SECURITY DEFINER paths. No EXECUTE grants or workflow semantics changed.
ALTER FUNCTION public.audit_operational_row_change() SET search_path = pg_catalog, public;
ALTER FUNCTION public.audit_patient_change() SET search_path = pg_catalog, public;
ALTER FUNCTION public.audit_patient_changes() SET search_path = pg_catalog, public;
ALTER FUNCTION public.fanout_notification_after_insert() SET search_path = pg_catalog, public;
ALTER FUNCTION public.generate_patient_code() SET search_path = pg_catalog, public;
ALTER FUNCTION public.handle_new_user() SET search_path = pg_catalog, public;
ALTER FUNCTION public.has_active_patient_visit_coverage(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.has_facility_access(uuid,uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.is_clinical_staff(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.lock_overdue_medication_slots() SET search_path = pg_catalog, public;
ALTER FUNCTION public.notify_due_medications() SET search_path = pg_catalog, public;
ALTER FUNCTION public.notify_insurance_claim_lifecycle() SET search_path = pg_catalog, public;
ALTER FUNCTION public.record_system_audit(text,text,text,uuid,text,jsonb) SET search_path = pg_catalog, public;
ALTER FUNCTION public.service_order_event_trigger() SET search_path = pg_catalog, public;
ALTER FUNCTION public.set_ward_facility_context() SET search_path = pg_catalog, public;
ALTER FUNCTION public.validate_service_order_encounter() SET search_path = pg_catalog, public;