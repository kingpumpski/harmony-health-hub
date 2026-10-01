-- Internal trigger functions must not be directly executable through the Data API.
-- PostgreSQL invokes trigger functions through their triggers without caller EXECUTE grants.
REVOKE ALL ON FUNCTION public.calculate_triage_bmi() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.clinical_reference_values_audit_stamp() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.enforce_ai_clinical_event_facility() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.enforce_clinical_facility_lineage() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ensure_invoice_number() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.prevent_notification_audit_mutation() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.refresh_invoice_totals() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sync_console_compatibility_columns() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sync_module_compatibility_columns() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.touch_care_transition_updated_at() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.touch_global_hims_updated_at() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.touch_mar_updated_at() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.touch_updated_at() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.validate_report_generation_item_transition() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.validate_report_generation_run_transition() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.validate_service_order_encounter() FROM PUBLIC, anon, authenticated, service_role;

DO $contract$
DECLARE
  v_function record;
BEGIN
  FOR v_function IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'calculate_triage_bmi',
        'clinical_reference_values_audit_stamp',
        'enforce_ai_clinical_event_facility',
        'enforce_clinical_facility_lineage',
        'ensure_invoice_number',
        'prevent_notification_audit_mutation',
        'refresh_invoice_totals',
        'sync_console_compatibility_columns',
        'sync_module_compatibility_columns',
        'touch_care_transition_updated_at',
        'touch_global_hims_updated_at',
        'touch_mar_updated_at',
        'touch_updated_at',
        'validate_report_generation_item_transition',
        'validate_report_generation_run_transition',
        'validate_service_order_encounter'
      )
  LOOP
    IF has_function_privilege('anon', v_function.signature, 'EXECUTE')
       OR has_function_privilege('authenticated', v_function.signature, 'EXECUTE')
       OR has_function_privilege('service_role', v_function.signature, 'EXECUTE') THEN
      RAISE EXCEPTION 'Internal trigger function remains directly executable: %', v_function.signature;
    END IF;
  END LOOP;
END;
$contract$;
