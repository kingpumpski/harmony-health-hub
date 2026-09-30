BEGIN;

CREATE OR REPLACE FUNCTION public.get_laboratory_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE result jsonb; v_department text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT NULLIF(lower(trim(p.department)),'') INTO v_department FROM public.profiles p WHERE p.id=auth.uid();
  IF NOT (
    public.has_role(auth.uid(),'admin') OR
    (public.has_role(auth.uid(),'lab_technician') AND (v_department IS NULL OR v_department='laboratory')) OR
    public.has_role(auth.uid(),'practitioner') OR
    (public.has_role(auth.uid(),'nurse') AND (v_department IS NULL OR v_department IN ('laboratory','clinical'))) OR
    (public.has_role(auth.uid(),'midwife') AND (v_department IS NULL OR v_department IN ('laboratory','clinical'))) OR
    (public.has_role(auth.uid(),'specialist_nurse') AND (v_department IS NULL OR v_department IN ('laboratory','clinical'))) OR
    (public.has_role(auth.uid(),'radiologist') AND (v_department IS NULL OR v_department='radiology'))
  ) THEN RAISE EXCEPTION 'Laboratory workspace access is not permitted'; END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit,200),1),500);
  SELECT jsonb_build_object(
    'patients', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name) FROM
      (SELECT id,first_name,last_name,patient_code FROM public.patients WHERE status <> 'inactive' ORDER BY first_name,last_name LIMIT _limit)p),'[]'::jsonb),
    'catalogue', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.test_name) FROM
      (SELECT id,test_code,test_name,category,specimen_type,unit,reference_low,reference_high,reference_text,default_charge,active,parameters FROM public.lab_test_catalogue WHERE active ORDER BY test_name LIMIT _limit)c),'[]'::jsonb),
    'orders', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC) FROM
      (SELECT id,patient_id,test_name,test_category,priority,status,created_at,clinical_notes,lab_test_catalogue_id FROM public.lab_orders ORDER BY created_at DESC LIMIT _limit)o),'[]'::jsonb),
    'results', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.entered_at DESC) FROM
      (SELECT id,lab_order_id,result_data,parameter_results,interpretation,is_abnormal,status,entered_at,approved_at,approved_by,numeric_value,unit,reference_low,reference_high,abnormal_flag FROM public.lab_results ORDER BY entered_at DESC LIMIT _limit)r),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.enter_lab_result_structured(
  _lab_order_id uuid,
  _parameter_results jsonb,
  _result_text text DEFAULT NULL,
  _interpretation text DEFAULT NULL,
  _is_abnormal boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  uid uuid := auth.uid();
  o public.lab_orders%ROWTYPE;
  c public.lab_test_catalogue%ROWTYPE;
  rid uuid;
  required_code text;
BEGIN
  IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'lab_technician')) THEN
    RAISE EXCEPTION 'Laboratory technician role required';
  END IF;
  IF jsonb_typeof(coalesce(_parameter_results,'{}'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'Structured laboratory results must be a JSON object';
  END IF;
  SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF o.status<>'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
  IF EXISTS(SELECT 1 FROM public.lab_results WHERE lab_order_id=o.id AND status IN('completed','approved')) THEN RAISE EXCEPTION 'A completed result already exists for this laboratory order'; END IF;
  IF o.lab_test_catalogue_id IS NOT NULL THEN
    SELECT * INTO c FROM public.lab_test_catalogue WHERE id=o.lab_test_catalogue_id;
    IF c.parameters IS NOT NULL AND jsonb_array_length(c.parameters) > 0 THEN
      FOR required_code IN
        SELECT value->>'code' FROM jsonb_array_elements(c.parameters) value
        WHERE coalesce((value->>'required')::boolean,false) = true AND nullif(value->>'code','') IS NOT NULL
      LOOP
        IF NOT (_parameter_results ? required_code) THEN RAISE EXCEPTION 'Required laboratory parameter is missing: %', required_code; END IF;
      END LOOP;
    END IF;
  END IF;
  INSERT INTO public.lab_results(lab_order_id,result_data,parameter_results,interpretation,is_abnormal,entered_by,status,numeric_value,unit,reference_low,reference_high,abnormal_flag,patient_id,result)
  VALUES(o.id,jsonb_build_object('value',coalesce(nullif(btrim(_result_text),''),_parameter_results::text)),coalesce(_parameter_results,'{}'::jsonb),_interpretation,_is_abnormal,uid,'completed',NULL,c.unit,c.reference_low,c.reference_high,CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END,o.patient_id,nullif(btrim(_result_text),''))
  RETURNING id INTO rid;
  UPDATE public.lab_orders SET status='completed',updated_at=now() WHERE id=o.id;
  RETURN rid;
END;
$$;

REVOKE ALL ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) TO authenticated;

COMMIT;
