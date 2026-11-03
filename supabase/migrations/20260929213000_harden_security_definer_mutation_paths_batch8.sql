-- Batch 8: harden remaining high-impact mutation/import SECURITY DEFINER paths.
-- Search-path hardening only; signatures, role gates, and workflow behavior are preserved.
--
-- The production baseline may already contain some of these RPCs while a clean
-- repository replay creates or omits them at different points in the chain.
-- Harden only functions that exist at this point, and never replace an already
-- empty search_path with a less restrictive value.
DO $batch8_mutation_function_paths$
DECLARE
  v_signature text;
  v_function regprocedure;
  v_config text[];
BEGIN
  FOR v_signature IN
    SELECT signature
    FROM (VALUES
      ('public.approve_diagnosis_import_batch(uuid)'),
      ('public.approve_legacy_migration_batch(uuid)'),
      ('public.create_ai_protocol_draft(text, text, integer, text)'),
      ('public.create_data_migration_batch(text, text, text, text, text, integer)'),
      ('public.create_reports_facility(text, text, text, text, text, text)'),
      ('public.create_service_catalogue_item(text, text, text, text, numeric, text)'),
      ('public.enter_lab_result(uuid, text, numeric, text, boolean)'),
      ('public.grant_service_order_override(uuid, text)'),
      ('public.import_approved_diagnosis_batch(uuid)'),
      ('public.import_service_tariffs(text, jsonb)'),
      ('public.import_stg_diagnoses(text, text, jsonb)'),
      ('public.mark_billing_items_billed(uuid, uuid[])'),
      ('public.mark_service_order_in_progress(uuid)')
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
$batch8_mutation_function_paths$;
