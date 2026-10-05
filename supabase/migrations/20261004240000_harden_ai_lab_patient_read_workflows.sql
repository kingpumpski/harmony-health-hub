CREATE OR REPLACE FUNCTION public.complete_outside_lab_ai_analysis(_document_id uuid,_analysis text)
RETURNS public.outside_lab_documents LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_uid uuid:=auth.uid(); v_document public.outside_lab_documents; v_patient_facility uuid; v_active_facility uuid:=public.current_user_facility_id();
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin') OR public.has_role(v_uid,'practitioner') OR public.has_role(v_uid,'nurse') OR public.has_role(v_uid,'midwife') OR public.has_role(v_uid,'specialist_nurse') OR public.has_role(v_uid,'radiologist') OR public.has_role(v_uid,'lab_technician')) THEN RAISE EXCEPTION 'Clinical role required to complete outside-lab AI analysis'; END IF;
 IF _document_id IS NULL OR NULLIF(pg_catalog.btrim(COALESCE(_analysis,'')),'') IS NULL THEN RAISE EXCEPTION 'Document id and AI analysis are required'; END IF;
 SELECT * INTO v_document FROM public.outside_lab_documents WHERE id=_document_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Outside-lab document not found'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v_document.patient_id;
 IF v_patient_facility IS NULL OR v_document.facility_id IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION 'Outside-lab document facility lineage is unresolved or inconsistent'; END IF;
 IF NOT(public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin')) AND (v_active_facility IS NULL OR v_active_facility<>v_patient_facility) THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 UPDATE public.outside_lab_documents SET ai_analysis=pg_catalog.btrim(_analysis),ai_analyzed_at=COALESCE(ai_analyzed_at,pg_catalog.now()) WHERE id=_document_id RETURNING * INTO v_document;
 PERFORM public.record_system_audit('outside_lab_ai_analysis_completed','outside_lab','outside_lab_document',v_document.id,'info',jsonb_build_object('patient_id',v_document.patient_id,'facility_id',v_document.facility_id));
 RETURN v_document;
END;$function$;
REVOKE ALL ON FUNCTION public.complete_outside_lab_ai_analysis(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_outside_lab_ai_analysis(uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.complete_outside_lab_ai_analysis(uuid,text) TO authenticated;
ALTER FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) SET search_path='';
REVOKE ALL ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) TO authenticated;
ALTER FUNCTION public.get_ai_clinical_context(uuid) SET search_path='';
REVOKE ALL ON FUNCTION public.get_ai_clinical_context(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_ai_clinical_context(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_ai_clinical_context(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_ai_report_requests(_patient_id uuid DEFAULT NULL,_limit integer DEFAULT 25)
RETURNS TABLE(id uuid,patient_id uuid,report_type text,requested_by uuid,status text,content text,error text,created_at timestamptz,completed_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_role public.app_role; v_limit integer; v_is_owner boolean;
BEGIN
 SELECT role INTO v_role FROM public.profiles WHERE id=auth.uid();
 IF v_role IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 SELECT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=_patient_id AND p.user_id=auth.uid()) INTO v_is_owner;
 IF NOT(v_is_owner OR v_role IN('admin','it_admin','practitioner','nurse','midwife','specialist_nurse','radiologist')) THEN RAISE EXCEPTION 'Not authorised'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 v_limit:=LEAST(GREATEST(COALESCE(_limit,25),1),50);
 RETURN QUERY SELECT r.id,r.patient_id,r.report_type,r.requested_by,r.status,r.content,r.error,r.created_at,r.completed_at FROM public.ai_report_requests r WHERE r.patient_id=_patient_id ORDER BY r.created_at DESC LIMIT v_limit;
END;$function$;
REVOKE ALL ON FUNCTION public.get_ai_report_requests(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_ai_report_requests(uuid,integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_ai_report_requests(uuid,integer) TO authenticated;
ALTER FUNCTION public.get_patient_invoices(uuid,integer) SET search_path='';
REVOKE ALL ON FUNCTION public.get_patient_invoices(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_patient_invoices(uuid,integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_patient_invoices(uuid,integer) TO authenticated;