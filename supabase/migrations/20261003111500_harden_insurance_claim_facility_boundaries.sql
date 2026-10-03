-- Enforce patient/facility lineage for insurance case and claim mutations.
DO $migration$
DECLARE
  v_signature regprocedure;
  v_definition text;
  v_anchor text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)'::regprocedure,
    'public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)'::regprocedure
  ] LOOP
    v_definition := pg_get_functiondef(v_signature);
    v_anchor := 'IF c.id IS NULL THEN RAISE EXCEPTION ''Claim not found''; END IF;';
    IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN
      RAISE EXCEPTION 'Claim existence anchor missing for %', v_signature;
    END IF;
    v_definition := replace(v_definition, v_anchor, v_anchor || E'
  PERFORM public.assert_patient_facility_context(c.patient_id);
  IF c.facility_id IS DISTINCT FROM (
    SELECT p.facility_id FROM public.patients p WHERE p.id=c.patient_id
  ) THEN
    RAISE EXCEPTION ''Insurance claim facility does not match patient facility'';
  END IF;
  IF c.invoice_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.invoices i
    WHERE i.id=c.invoice_id AND i.patient_id=c.patient_id
      AND i.facility_id=c.facility_id
  ) THEN
    RAISE EXCEPTION ''Insurance claim invoice does not match patient and facility'';
  END IF;');
    EXECUTE v_definition;
    EXECUTE format('ALTER FUNCTION %s SET search_path TO %L', v_signature, 'pg_catalog, public');
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);
  END LOOP;

  v_signature := 'public.update_insurance_case(uuid,text,text,text,numeric,numeric,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_signature);
  v_anchor := 'UPDATE public.insurance_cases SET';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN
    RAISE EXCEPTION 'Insurance case update anchor missing';
  END IF;
  v_definition := replace(v_definition,
    'DECLARE v public.insurance_cases;',
    'DECLARE v public.insurance_cases; v_patient_id uuid; v_case_facility uuid; v_patient_facility uuid;');
  v_definition := replace(v_definition, v_anchor, E'SELECT ic.patient_id,ic.facility_id INTO v_patient_id,v_case_facility FROM public.insurance_cases ic WHERE ic.id=_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION ''Insurance case not found''; END IF;
  PERFORM public.assert_patient_facility_context(v_patient_id);
  SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=v_patient_id;
  IF v_patient_facility IS NULL OR v_case_facility IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION ''Insurance case facility does not match patient facility'';
  END IF;
  ' || v_anchor);
  EXECUTE v_definition;
  EXECUTE format('ALTER FUNCTION %s SET search_path TO %L', v_signature, 'pg_catalog, public');
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);

  PERFORM pg_notify('pgrst', 'reload schema');
END;
$migration$;
