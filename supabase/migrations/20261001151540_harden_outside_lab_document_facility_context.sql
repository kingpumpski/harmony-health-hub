-- Restore repository parity for outside-laboratory document facility boundaries.
CREATE OR REPLACE FUNCTION public.register_outside_lab_document(_patient_id uuid, _document_type text, _title text, _storage_path text, _mime_type text DEFAULT NULL::text)
RETURNS public.outside_lab_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_doc public.outside_lab_documents;
  v_facility uuid;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin') OR public.has_role(v_uid,'practitioner') OR public.has_role(v_uid,'nurse') OR public.has_role(v_uid,'midwife') OR public.has_role(v_uid,'specialist_nurse') OR public.has_role(v_uid,'lab_technician')) THEN
    RAISE EXCEPTION 'Outside-lab document upload is not permitted';
  END IF;
  v_facility := public.assert_patient_facility_context(_patient_id);
  IF NULLIF(pg_catalog.btrim(_document_type),'') IS NULL THEN RAISE EXCEPTION 'Document type is required'; END IF;
  IF NULLIF(pg_catalog.btrim(_storage_path),'') IS NULL OR position('/' IN _storage_path)=0 THEN RAISE EXCEPTION 'Invalid storage path'; END IF;
  IF split_part(_storage_path,'/',1) <> _patient_id::text THEN RAISE EXCEPTION 'Storage path must be scoped to the patient'; END IF;
  INSERT INTO public.outside_lab_documents(patient_id,facility_id,document_type,title,storage_path,mime_type,uploaded_by)
  VALUES (_patient_id,v_facility,btrim(_document_type),COALESCE(NULLIF(btrim(_title),''),'Outside laboratory document'),_storage_path,NULLIF(btrim(_mime_type),''),v_uid)
  RETURNING * INTO v_doc;
  PERFORM public.record_system_audit('outside_lab_document_uploaded','outside_lab','outside_lab_document',v_doc.id,'info',jsonb_build_object('patient_id',_patient_id,'facility_id',v_facility,'document_type',_document_type));
  RETURN v_doc;
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_outside_lab_ai_analysis(_document_id uuid, _analysis text)
RETURNS public.outside_lab_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_document public.outside_lab_documents;
  v_patient_facility uuid;
  v_active_facility uuid := public.current_user_facility_id();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin') OR public.has_role(v_uid,'practitioner') OR public.has_role(v_uid,'nurse') OR public.has_role(v_uid,'midwife') OR public.has_role(v_uid,'specialist_nurse') OR public.has_role(v_uid,'radiologist') OR public.has_role(v_uid,'lab_technician')) THEN
    RAISE EXCEPTION 'Clinical role required to complete outside-lab AI analysis';
  END IF;
  IF _document_id IS NULL OR NULLIF(btrim(COALESCE(_analysis,'')),'') IS NULL THEN RAISE EXCEPTION 'Document id and AI analysis are required'; END IF;
  SELECT * INTO v_document FROM public.outside_lab_documents WHERE id=_document_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Outside-lab document not found'; END IF;
  SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v_document.patient_id;
  IF v_patient_facility IS NULL OR v_document.facility_id IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION 'Outside-lab document facility lineage is unresolved or inconsistent'; END IF;
  IF NOT (public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin')) AND (v_active_facility IS NULL OR v_active_facility <> v_patient_facility) THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
  UPDATE public.outside_lab_documents SET ai_analysis=btrim(_analysis),ai_analyzed_at=COALESCE(ai_analyzed_at,now()) WHERE id=_document_id RETURNING * INTO v_document;
  PERFORM public.record_system_audit('outside_lab_ai_analysis_completed','outside_lab','outside_lab_document',v_document.id,'info',jsonb_build_object('patient_id',v_document.patient_id,'facility_id',v_document.facility_id));
  RETURN v_document;
END;
$function$;

REVOKE ALL ON FUNCTION public.register_outside_lab_document(uuid,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_outside_lab_document(uuid,text,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.complete_outside_lab_ai_analysis(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_outside_lab_ai_analysis(uuid,text) TO authenticated;
