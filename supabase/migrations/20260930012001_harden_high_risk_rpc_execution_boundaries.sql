-- Reconcile explicit execution boundaries and SECURITY DEFINER search paths for the
-- selected high-risk patient-scoped application RPCs.
--
-- This migration does NOT enable patient/facility tenancy. Those workflows remain
-- classified as pending until isolated two-facility regression evidence exists.
--
-- The production baseline may contain RPCs that are not present at this point in
-- a clean repository replay. Apply the execution boundary only when the exact
-- function signature exists; later source migrations remain responsible for
-- creating and granting their own canonical RPC definitions.
DO $high_risk_rpc_execution_boundaries$
DECLARE
  v_signature text;
  v_function regprocedure;
  v_config text[];
BEGIN
  FOR v_signature IN
    SELECT signature
    FROM (VALUES
      ('public.create_ai_clinical_session(uuid,text,jsonb,jsonb)'),
      ('public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric)'),
      ('public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric)'),
      ('public.create_insurance_claim_draft(uuid,text,text,numeric,uuid)'),
      ('public.create_pharmacy_pos_sale(uuid,uuid,integer)'),
      ('public.update_patient_workflow(uuid,jsonb)'),
      ('public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text)'),
      ('public.search_patient_directory(text,integer)')
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

      EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_function);
      EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_function);
    END IF;
  END LOOP;
END;
$high_risk_rpc_execution_boundaries$;

NOTIFY pgrst, 'reload schema';
