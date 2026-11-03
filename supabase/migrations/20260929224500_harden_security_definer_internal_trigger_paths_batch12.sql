-- Batch 12: harden internal/trigger SECURITY DEFINER paths.
-- No EXECUTE grants or workflow semantics are changed.
-- Harden only functions present at this point and preserve an empty search_path.
DO $batch12_internal_trigger_paths$
DECLARE
  v_signature text;
  v_function regprocedure;
  v_config text[];
BEGIN
  FOR v_signature IN
    SELECT signature
    FROM (VALUES
      ('public.audit_operational_row_change()'),
      ('public.audit_patient_change()'),
      ('public.audit_patient_changes()'),
      ('public.fanout_notification_after_insert()'),
      ('public.generate_patient_code()'),
      ('public.handle_new_user()'),
      ('public.has_active_patient_visit_coverage(uuid)'),
      ('public.has_facility_access(uuid,uuid)'),
      ('public.is_clinical_staff(uuid)'),
      ('public.lock_overdue_medication_slots()'),
      ('public.notify_due_medications()'),
      ('public.notify_insurance_claim_lifecycle()'),
      ('public.record_system_audit(text,text,text,uuid,text,jsonb)'),
      ('public.service_order_event_trigger()'),
      ('public.set_ward_facility_context()'),
      ('public.validate_service_order_encounter()')
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
$batch12_internal_trigger_paths$;
