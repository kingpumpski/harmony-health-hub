BEGIN;

CREATE OR REPLACE FUNCTION public.create_lab_test_catalogue_item_with_parameters(
  _test_code text,
  _test_name text,
  _category text,
  _specimen_type text,
  _unit text,
  _reference_low numeric,
  _reference_high numeric,
  _reference_text text,
  _default_charge numeric,
  _turnaround_minutes integer,
  _parameters jsonb DEFAULT '[]'::jsonb
)
RETURNS public.lab_test_catalogue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  r public.lab_test_catalogue;
  v_uid uuid := auth.uid();
  v_parameter jsonb;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.current_user_has_catalogue_create_permission('create_items')
     AND NOT public.current_user_has_catalogue_create_permission('create_services') THEN
    RAISE EXCEPTION 'Create items or services privilege required';
  END IF;
  IF length(trim(coalesce(_test_code,''))) < 2 THEN RAISE EXCEPTION 'Test code is required'; END IF;
  IF length(trim(coalesce(_test_name,''))) < 2 THEN RAISE EXCEPTION 'Test name is required'; END IF;
  IF coalesce(_default_charge,0) < 0 THEN RAISE EXCEPTION 'Charge cannot be negative'; END IF;
  IF coalesce(_turnaround_minutes,0) < 0 THEN RAISE EXCEPTION 'Turnaround time cannot be negative'; END IF;
  IF _reference_low IS NOT NULL AND _reference_high IS NOT NULL AND _reference_low > _reference_high THEN
    RAISE EXCEPTION 'Reference low cannot exceed reference high';
  END IF;
  IF jsonb_typeof(coalesce(_parameters,'[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'Laboratory parameters must be a JSON array';
  END IF;
  IF jsonb_array_length(coalesce(_parameters,'[]'::jsonb)) > 100 THEN
    RAISE EXCEPTION 'A test may define at most 100 parameters';
  END IF;

  FOR v_parameter IN SELECT value FROM jsonb_array_elements(coalesce(_parameters,'[]'::jsonb)) AS items(value)
  LOOP
    v_code := nullif(pg_catalog.btrim(v_parameter->>'code'),'');
    IF jsonb_typeof(v_parameter) <> 'object' OR v_code IS NULL THEN
      RAISE EXCEPTION 'Each laboratory parameter must be an object with a non-empty code';
    END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(coalesce(_parameters,'[]'::jsonb)) AS items(value)
      WHERE nullif(pg_catalog.btrim(value->>'code'),'') = v_code
      GROUP BY nullif(pg_catalog.btrim(value->>'code'),'')
      HAVING count(*) > 1
    ) THEN
      RAISE EXCEPTION 'Laboratory parameter codes must be unique: %', v_code;
    END IF;
    IF coalesce(v_parameter->>'type','text') NOT IN ('text','numeric','number','boolean','select') THEN
      RAISE EXCEPTION 'Unsupported laboratory parameter type for %', v_code;
    END IF;
    IF v_parameter ? 'required' AND jsonb_typeof(v_parameter->'required') <> 'boolean' THEN
      RAISE EXCEPTION 'Parameter required must be boolean for %', v_code;
    END IF;
    IF (v_parameter ? 'reference_low' AND jsonb_typeof(v_parameter->'reference_low') NOT IN ('number','null'))
       OR (v_parameter ? 'reference_high' AND jsonb_typeof(v_parameter->'reference_high') NOT IN ('number','null')) THEN
      RAISE EXCEPTION 'Parameter reference bounds must be numeric for %', v_code;
    END IF;
    IF v_parameter->>'reference_low' IS NOT NULL AND v_parameter->>'reference_high' IS NOT NULL
       AND (v_parameter->>'reference_low')::numeric > (v_parameter->>'reference_high')::numeric THEN
      RAISE EXCEPTION 'Parameter reference low cannot exceed high for %', v_code;
    END IF;
  END LOOP;

  INSERT INTO public.lab_test_catalogue(
    test_code,test_name,category,specimen_type,unit,reference_low,reference_high,
    reference_text,default_charge,turnaround_minutes,active,parameters
  )
  VALUES(
    upper(pg_catalog.btrim(_test_code)),
    pg_catalog.btrim(_test_name),
    nullif(pg_catalog.btrim(coalesce(_category,'')),''),
    nullif(pg_catalog.btrim(coalesce(_specimen_type,'')),''),
    nullif(pg_catalog.btrim(coalesce(_unit,'')),''),
    _reference_low,_reference_high,
    nullif(pg_catalog.btrim(coalesce(_reference_text,'')),''),
    coalesce(_default_charge,0),coalesce(_turnaround_minutes,0),true,
    coalesce(_parameters,'[]'::jsonb)
  )
  RETURNING * INTO r;

  PERFORM public.record_system_audit(
    'lab_test_catalogue_created',
    'laboratory',
    'lab_test_catalogue',
    r.id,
    'info',
    jsonb_build_object('test_code',r.test_code,'test_name',r.test_name,'parameter_count',jsonb_array_length(coalesce(r.parameters,'[]'::jsonb)))
  );
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_lab_test_catalogue_item_with_parameters(text,text,text,text,text,numeric,numeric,text,numeric,integer,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_lab_test_catalogue_item_with_parameters(text,text,text,text,text,numeric,numeric,text,numeric,integer,jsonb) TO authenticated;

COMMIT;
