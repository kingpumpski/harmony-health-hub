-- Gate A: reconcile legacy admission, amendment, order and submission SECURITY DEFINER functions.
-- The shared attribution helper enforces authentication, clinical role, resolved facility,
-- TEST-0001 isolation before admin exceptions, and active-facility consistency.
DO $migration$
DECLARE
  v_definition text;
  v_signature regprocedure;
  v_anchor text;
  v_replacement text;
  v_name text;
  v_functions text[] := ARRAY[
    'public.admit_encounter_workflow(uuid,text,text,boolean)',
    'public.amend_encounter_workflow(uuid,text,text,text,text,text)',
    'public.create_encounter_imaging_order(uuid,text,text,text,text,text)',
    'public.create_encounter_lab_order(uuid,text,text,text)',
    'public.create_encounter_service_order(uuid,text,text)',
    'public.submit_encounter_workflow(uuid,text,timestamp with time zone,text)'
  ];
BEGIN
  FOREACH v_name IN ARRAY v_functions LOOP
    v_signature := v_name::regprocedure;
    v_definition := pg_catalog.pg_get_functiondef(v_signature);

    IF v_name = 'public.admit_encounter_workflow(uuid,text,text,boolean)' THEN
      v_anchor := 'IF NOT FOUND THEN RAISE EXCEPTION ''Encounter not found''; END IF;';
      v_replacement := v_anchor || E'\n  PERFORM public.ensure_encounter_facility_attribution(_encounter_id);\n  SELECT * INTO v_enc FROM public.encounters WHERE id = _encounter_id FOR UPDATE;';
    ELSIF v_name = 'public.amend_encounter_workflow(uuid,text,text,text,text,text)' THEN
      v_anchor := 'IF v_enc.id IS NULL THEN RAISE EXCEPTION ''Encounter not found''; END IF;';
      v_replacement := v_anchor || E'\n  PERFORM public.ensure_encounter_facility_attribution(_encounter_id);\n  SELECT * INTO v_enc FROM public.encounters WHERE id = _encounter_id FOR UPDATE;';
    ELSIF v_name = 'public.create_encounter_imaging_order(uuid,text,text,text,text,text)' THEN
      v_anchor := 'if not found then raise exception ''Encounter not found''; end if;';
      v_replacement := v_anchor || E'\n  PERFORM public.ensure_encounter_facility_attribution(_encounter_id);\n  SELECT * INTO e FROM public.encounters WHERE id=_encounter_id FOR UPDATE;';
    ELSIF v_name = 'public.create_encounter_lab_order(uuid,text,text,text)' THEN
      v_anchor := 'if not found then raise exception ''Encounter not found''; end if;';
      v_replacement := v_anchor || E'\n  PERFORM public.ensure_encounter_facility_attribution(_encounter_id);\n  SELECT * INTO e FROM public.encounters WHERE id=_encounter_id FOR UPDATE;';
    ELSIF v_name = 'public.create_encounter_service_order(uuid,text,text)' THEN
      v_anchor := 'if not found then raise exception ''Encounter not found''; end if;';
      v_replacement := v_anchor || E'\n  PERFORM public.ensure_encounter_facility_attribution(_encounter_id);\n  SELECT * INTO e FROM public.encounters WHERE id=_encounter_id FOR UPDATE;';
    ELSE
      v_anchor := 'IF v_enc.id IS NULL THEN RAISE EXCEPTION ''Encounter not found''; END IF;';
      v_replacement := v_anchor || E'\n  PERFORM public.ensure_encounter_facility_attribution(_encounter_id);\n  SELECT * INTO v_enc FROM public.encounters WHERE id = _encounter_id FOR UPDATE;';
    END IF;

    IF pg_catalog.position(v_anchor in v_definition) = 0 THEN
      RAISE EXCEPTION 'Expected insertion anchor not found for %', v_name;
    END IF;

    v_definition := pg_catalog.replace(v_definition, v_anchor, v_replacement);
    EXECUTE v_definition;
  END LOOP;
END;
$migration$;

ALTER FUNCTION public.admit_encounter_workflow(uuid,text,text,boolean) SET search_path='';
ALTER FUNCTION public.amend_encounter_workflow(uuid,text,text,text,text,text) SET search_path='';
ALTER FUNCTION public.create_encounter_imaging_order(uuid,text,text,text,text,text) SET search_path='';
ALTER FUNCTION public.create_encounter_lab_order(uuid,text,text,text) SET search_path='';
ALTER FUNCTION public.create_encounter_service_order(uuid,text,text) SET search_path='';
ALTER FUNCTION public.submit_encounter_workflow(uuid,text,timestamp with time zone,text) SET search_path='';

REVOKE ALL ON FUNCTION public.admit_encounter_workflow(uuid,text,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_encounter_workflow(uuid,text,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.amend_encounter_workflow(uuid,text,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.amend_encounter_workflow(uuid,text,text,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.create_encounter_imaging_order(uuid,text,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_imaging_order(uuid,text,text,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.create_encounter_lab_order(uuid,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_lab_order(uuid,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.create_encounter_service_order(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_service_order(uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.submit_encounter_workflow(uuid,text,timestamp with time zone,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.submit_encounter_workflow(uuid,text,timestamp with time zone,text) TO authenticated;

NOTIFY pgrst,'reload schema';