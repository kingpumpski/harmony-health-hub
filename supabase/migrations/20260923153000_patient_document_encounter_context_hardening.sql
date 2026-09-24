-- Strengthen patient document and encounter entrypoint context.
CREATE OR REPLACE FUNCTION public.create_patient_document(_patient_id UUID,_document_type TEXT,_file_url TEXT,_notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID; uid UUID:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Document creation is not permitted'; END IF;
 IF _patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF NULLIF(trim(_document_type),'') IS NULL THEN RAISE EXCEPTION 'Document type is required'; END IF;
 IF NULLIF(trim(_file_url),'') IS NULL THEN RAISE EXCEPTION 'Document file reference is required'; END IF;
 INSERT INTO public.patient_documents(patient_id,document_type,file_url,notes,uploaded_by)
 VALUES(_patient_id,trim(_document_type),trim(_file_url),_notes,uid) RETURNING id INTO v_id;
 RETURN jsonb_build_object('document_id',v_id);
END; $$;

CREATE OR REPLACE FUNCTION public.create_encounter_workflow(_patient_id UUID,_symptoms TEXT DEFAULT NULL,_clerking_notes TEXT DEFAULT NULL)
RETURNS public.encounters LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.encounters; uid UUID:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Only authorized clinical staff may create encounters'; END IF;
 IF _patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF NULLIF(trim(COALESCE(_symptoms,'')),'') IS NULL AND NULLIF(trim(COALESCE(_clerking_notes,'')),'') IS NULL THEN RAISE EXCEPTION 'Encounter clinical information is required'; END IF;
 INSERT INTO public.encounters(patient_id,symptoms,clerking_notes,practitioner_id,status)
 VALUES(_patient_id,NULLIF(trim(_symptoms),''),NULLIF(trim(_clerking_notes),''),uid,'draft')
 RETURNING * INTO result;
 RETURN result;
END; $$;

REVOKE ALL ON FUNCTION public.create_patient_document(UUID,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_encounter_workflow(UUID,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_patient_document(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_encounter_workflow(UUID,TEXT,TEXT) TO authenticated;
