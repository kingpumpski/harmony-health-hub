-- Batch 8: harden remaining high-impact mutation/import SECURITY DEFINER paths.
-- Search-path hardening only; signatures, role gates, and workflow behavior are preserved.
ALTER FUNCTION public.approve_diagnosis_import_batch(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.approve_legacy_migration_batch(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_ai_protocol_draft(text, text, integer, text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_data_migration_batch(text, text, text, text, text, integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_reports_facility(text, text, text, text, text, text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_service_catalogue_item(text, text, text, text, numeric, text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.enter_lab_result(uuid, text, numeric, text, boolean) SET search_path = pg_catalog, public;
ALTER FUNCTION public.grant_service_order_override(uuid, text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.import_approved_diagnosis_batch(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.import_service_tariffs(text, jsonb) SET search_path = pg_catalog, public;
ALTER FUNCTION public.import_stg_diagnoses(text, text, jsonb) SET search_path = pg_catalog, public;
ALTER FUNCTION public.mark_billing_items_billed(uuid, uuid[]) SET search_path = pg_catalog, public;
ALTER FUNCTION public.mark_service_order_in_progress(uuid) SET search_path = pg_catalog, public;
