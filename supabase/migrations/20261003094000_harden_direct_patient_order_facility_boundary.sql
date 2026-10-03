-- Gate A: enforce TEST-0001 isolation in directly callable service-order and lab/imaging order helpers.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text := 'IF NOT FOUND THEN RAISE EXCEPTION ''Active patient does not exist''; END IF;';
  v_name text;
  v_functions text[] := ARRAY[
    'public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid)',
    'public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric)'
  ];
BEGIN
  FOREACH v_name IN ARRAY v_functions LOOP
    v_definition := pg_catalog.pg_get_functiondef(v_name::regprocedure);
    IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
      RAISE EXCEPTION 'Expected active-patient validation anchor not found for %',v_name;
    END IF;
    v_definition := pg_catalog.replace(v_definition,v_anchor,v_anchor || E'\\n PERFORM public.assert_patient_facility_context(_patient_id);');
    EXECUTE v_definition;
  END LOOP;
END;
$migration$;

ALTER FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid) SET search_path='';
ALTER FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) SET search_path='';
REVOKE ALL ON FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) TO authenticated;

-- create_service_order is also a client-callable RPC used by non-encounter workflows.
-- Keep that workflow, but require the patient facility assertion and persist the facility.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
BEGIN
  v_definition := pg_catalog.pg_get_functiondef('public.create_service_order(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text)'::regprocedure);
  v_anchor := 'IF _patient_id IS NULL OR NULLIF(pg_catalog.btrim(_service_name),'''') IS NULL THEN RAISE EXCEPTION ''Patient and service name are required''; END IF;';
  IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
    RAISE EXCEPTION 'Expected patient validation anchor not found for create_service_order';
  END IF;
  v_definition := pg_catalog.replace(v_definition,v_anchor,v_anchor || E'\n PERFORM public.assert_patient_facility_context(_patient_id);');
  v_anchor := 'IF _encounter_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.encounters e WHERE e.id=_encounter_id AND e.patient_id=_patient_id) THEN RAISE EXCEPTION ''Encounter does not belong to this patient''; END IF;';
  IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
    RAISE EXCEPTION 'Expected encounter linkage anchor not found for create_service_order';
  END IF;
  v_definition := pg_catalog.replace(v_definition,v_anchor,'IF _encounter_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.encounters e WHERE e.id=_encounter_id AND e.patient_id=_patient_id AND e.facility_id=(SELECT p.facility_id FROM public.patients p WHERE p.id=_patient_id)) THEN RAISE EXCEPTION ''Encounter does not belong to this patient facility''; END IF;');
  v_anchor := 'order_type,service_code,status,created_by) VALUES';
  IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
    RAISE EXCEPTION 'Expected service order insert anchor not found';
  END IF;
  v_definition := pg_catalog.replace(v_definition,v_anchor,'order_type,service_code,status,created_by,facility_id) VALUES');
  v_anchor := 'COALESCE(_order_type,''service''),_service_code,''pending_payment_approval'',auth.uid()) RETURNING * INTO v_order;';
  IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
    RAISE EXCEPTION 'Expected service order values anchor not found';
  END IF;
  v_definition := pg_catalog.replace(v_definition,v_anchor,'COALESCE(_order_type,''service''),_service_code,''pending_payment_approval'',auth.uid(),(SELECT p.facility_id FROM public.patients p WHERE p.id=_patient_id)) RETURNING * INTO v_order;');
  EXECUTE v_definition;
END;
$migration$;

ALTER FUNCTION public.create_service_order(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text) SET search_path='';
REVOKE ALL ON FUNCTION public.create_service_order(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_service_order(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text) TO authenticated;

NOTIFY pgrst,'reload schema';