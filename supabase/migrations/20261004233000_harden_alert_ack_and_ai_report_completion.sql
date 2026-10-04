ALTER FUNCTION public.acknowledge_medication_alert(uuid) SET search_path='';
REVOKE ALL ON FUNCTION public.acknowledge_medication_alert(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acknowledge_medication_alert(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_medication_alert(uuid) TO authenticated;
ALTER FUNCTION public.acknowledge_vital_alert(uuid) SET search_path='';
REVOKE ALL ON FUNCTION public.acknowledge_vital_alert(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acknowledge_vital_alert(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_vital_alert(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.complete_ai_report_request(_request_id uuid,_content text DEFAULT NULL,_error text DEFAULT NULL)
RETURNS public.ai_report_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE uid uuid:=auth.uid(); v_request public.ai_report_requests; v_content text:=NULLIF(pg_catalog.btrim(coalesce(_content,'')),''); v_error text:=NULLIF(pg_catalog.btrim(coalesce(_error,'')),''); v_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT * INTO v_request FROM public.ai_report_requests WHERE id=_request_id FOR UPDATE;
 IF v_request.id IS NULL THEN RAISE EXCEPTION 'Report request not found'; END IF;
 IF v_request.facility_id IS NULL THEN RAISE EXCEPTION 'Report request facility attribution is unresolved'; END IF;
 v_facility:=public.current_user_facility_id();
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_facility IS NULL OR v_request.facility_id IS DISTINCT FROM v_facility) THEN RAISE EXCEPTION 'Report request belongs to a different facility context'; END IF;
 IF NOT(v_request.requested_by=uid OR public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'radiologist')) THEN RAISE EXCEPTION 'Not authorised to complete this patient report'; END IF;
 IF v_request.status<>'processing' THEN IF v_request.status IN('completed','failed') THEN RETURN v_request; END IF; RAISE EXCEPTION 'Report request is not processing'; END IF;
 IF v_content IS NULL AND v_error IS NULL THEN RAISE EXCEPTION 'Report content or error is required'; END IF;
 UPDATE public.ai_report_requests SET status=CASE WHEN v_content IS NOT NULL THEN 'completed' ELSE 'failed' END,content=CASE WHEN v_content IS NOT NULL THEN v_content ELSE NULL END,error=CASE WHEN v_content IS NULL THEN v_error ELSE NULL END,completed_at=pg_catalog.now() WHERE id=_request_id RETURNING * INTO v_request;
 RETURN v_request;
END;$function$;
REVOKE ALL ON FUNCTION public.complete_ai_report_request(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_ai_report_request(uuid,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.complete_ai_report_request(uuid,text,text) TO authenticated;