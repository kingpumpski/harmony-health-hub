-- Batch 11: harden authenticated SECURITY DEFINER API paths. Search-path only.
-- Some targets are supplied by the production baseline or later local migrations.
-- Harden only functions present at this point and preserve an empty search_path.
DO $batch11_authenticated_api_paths$
DECLARE
  v_signature text;
  v_function regprocedure;
  v_config text[];
BEGIN
  FOR v_signature IN
    SELECT signature
    FROM (VALUES
      ('public.find_legacy_patient_candidates(uuid)'),
      ('public.find_pharmacy_alternatives(text,text)'),
      ('public.get_ai_case_memory_for_diagnosis(text,integer)'),
      ('public.get_ai_report_requests(uuid,integer)'),
      ('public.get_appointment_clinician()'),
      ('public.get_appointment_clinicians()'),
      ('public.get_current_facility_context()'),
      ('public.get_it_support_system_logs(text,text,integer)'),
      ('public.get_legacy_patient_candidates(uuid)'),
      ('public.get_missing_billing_tariffs(uuid)'),
      ('public.get_my_permissions()'),
      ('public.get_pending_specialist_referrals()'),
      ('public.get_staff_signature_for_report(uuid)'),
      ('public.get_workflow_notifications(integer)'),
      ('public.notification_feature_enabled(text,uuid)'),
      ('public.promote_legacy_migration_batch(uuid)'),
      ('public.reconcile_legacy_migration_row(uuid,uuid,numeric,text)'),
      ('public.reconcile_legacy_record_patient(uuid,uuid,text)'),
      ('public.record_ai_clinical_event(uuid,text,jsonb)'),
      ('public.reopen_own_document(text,uuid)'),
      ('public.replace_role_permissions(public.app_role,text[])'),
      ('public.set_facility_notification_provider(uuid,text,text,text,text,text,text,jsonb)'),
      ('public.set_facility_notification_provider(uuid,text,text,text,text,text,text)'),
      ('public.set_staff_shift_assignment_active(uuid,boolean)'),
      ('public.stage_data_migration_rows(uuid,jsonb)'),
      ('public.transition_ai_protocol(uuid,text)'),
      ('public.validate_diagnosis_import_batch(uuid)'),
      ('public.validate_legacy_migration_batch(uuid)'),
      ('public.validate_legacy_record(uuid)')
    ) AS signatures(signature)
  LOOP
    v_function := pg_catalog.to_regprocedure(v_signature);
    IF v_function IS NOT NULL THEN
      SELECT p.proconfig INTO v_config
      FROM pg_catalog.pg_proc p
      WHERE p.oid = v_function;

      IF NOT COALESCE(v_config @> ARRAY['search_path=""'], false) THEN
        EXECUTE pg_catalog.format(
          'ALTER FUNCTION %s SET search_path = pg_catalog, public',
          v_function
        );
      END IF;
    END IF;
  END LOOP;
END;
$batch11_authenticated_api_paths$;
