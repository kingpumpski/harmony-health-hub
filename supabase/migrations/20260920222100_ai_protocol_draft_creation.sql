CREATE OR REPLACE FUNCTION public.create_ai_protocol_draft(_diagnosis text,_protocol_text text,_case_count integer,_icd_code text DEFAULT NULL)
RETURNS public.ai_protocols
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_row public.ai_protocols;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Not authorised'; END IF;
  IF _diagnosis IS NULL OR btrim(_diagnosis)='' THEN RAISE EXCEPTION 'Diagnosis is required'; END IF;
  IF _protocol_text IS NULL OR btrim(_protocol_text)='' THEN RAISE EXCEPTION 'Protocol text is required'; END IF;
  IF COALESCE(_case_count,0) < 3 THEN RAISE EXCEPTION 'At least 3 cases are required'; END IF;
  INSERT INTO public.ai_protocols(diagnosis,icd_code,protocol_text,case_count,status)
  VALUES (btrim(_diagnosis),NULLIF(btrim(_icd_code),''),_protocol_text,_case_count,'pending_review')
  RETURNING * INTO v_row;
  RETURN v_row;
END; $$;
REVOKE ALL ON FUNCTION public.create_ai_protocol_draft(text,text,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_ai_protocol_draft(text,text,integer,text) TO authenticated;
