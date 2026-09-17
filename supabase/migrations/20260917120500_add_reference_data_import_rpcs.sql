CREATE OR REPLACE FUNCTION public.import_stg_diagnoses(_standard_code TEXT,_source_version TEXT,_rows JSONB)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_standard_id UUID; v_item JSONB; v_count INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  SELECT id INTO v_standard_id FROM public.diagnosis_standards WHERE code=_standard_code AND is_active ORDER BY created_at DESC LIMIT 1;
  IF v_standard_id IS NULL THEN
    INSERT INTO public.diagnosis_standards(code,name,jurisdiction,version,publisher,is_default,is_active)
    VALUES (_standard_code,CASE WHEN _standard_code='GH-STG' THEN 'Ghana Standard Treatment Guidelines' ELSE _standard_code END,'Ghana',_source_version,'Ghana Ministry of Health',_standard_code='GH-STG',true)
    RETURNING id INTO v_standard_id;
  END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(_rows,'[]'::jsonb)) LOOP
    INSERT INTO public.stg_diagnoses(standard_id,code,display_name,description,category,synonyms,source_reference,is_active)
    VALUES (v_standard_id,trim(v_item->>'code'),COALESCE(NULLIF(trim(v_item->>'display_name'),''),trim(v_item->>'name')),NULLIF(trim(v_item->>'description'),''),NULLIF(trim(v_item->>'category'),''),ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_item->'synonyms','[]'::jsonb))),NULLIF(trim(v_item->>'source_reference'),''),COALESCE((v_item->>'is_active')::boolean,true))
    ON CONFLICT (standard_id,code) DO UPDATE SET display_name=EXCLUDED.display_name,description=EXCLUDED.description,category=EXCLUDED.category,synonyms=EXCLUDED.synonyms,source_reference=EXCLUDED.source_reference,is_active=EXCLUDED.is_active,updated_at=now();
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END; $$;
REVOKE ALL ON FUNCTION public.import_stg_diagnoses(TEXT,TEXT,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.import_stg_diagnoses(TEXT,TEXT,JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.import_service_tariffs(_source_standard TEXT,_rows JSONB)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_item JSONB; v_count INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(_rows,'[]'::jsonb)) LOOP
    INSERT INTO public.service_tariffs(service_code,service_name,department,unit,amount,active,source_standard,effective_from,effective_to,currency,metadata)
    VALUES (trim(v_item->>'service_code'),trim(v_item->>'service_name'),COALESCE(NULLIF(trim(v_item->>'department'),''),'General'),COALESCE(NULLIF(trim(v_item->>'unit'),''),'service'),COALESCE((v_item->>'amount')::numeric,0),COALESCE((v_item->>'active')::boolean,true),_source_standard,NULLIF(v_item->>'effective_from','')::date,NULLIF(v_item->>'effective_to','')::date,COALESCE(NULLIF(v_item->>'currency',''),'GHS'),COALESCE(v_item->'metadata','{}'::jsonb))
    ON CONFLICT (service_code) DO UPDATE SET service_name=EXCLUDED.service_name,department=EXCLUDED.department,unit=EXCLUDED.unit,amount=EXCLUDED.amount,active=EXCLUDED.active,source_standard=EXCLUDED.source_standard,effective_from=EXCLUDED.effective_from,effective_to=EXCLUDED.effective_to,currency=EXCLUDED.currency,metadata=EXCLUDED.metadata,updated_at=now();
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END; $$;
REVOKE ALL ON FUNCTION public.import_service_tariffs(TEXT,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.import_service_tariffs(TEXT,JSONB) TO authenticated;
