-- Harden legacy Patient Hub clinical entrypoints with explicit patient context.
-- Preserve their existing signatures while preventing writes against missing/inactive patients.

CREATE OR REPLACE FUNCTION public.create_encounter_workflow(
  _patient_id UUID,
  _symptoms TEXT DEFAULT NULL,
  _clerking_notes TEXT DEFAULT NULL
)
RETURNS public.encounters
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE result public.encounters;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'practitioner') OR
    public.has_role(auth.uid(), 'nurse') OR public.has_role(auth.uid(), 'midwife') OR
    public.has_role(auth.uid(), 'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Only authorized clinical staff may create encounters'; END IF;
  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id AND COALESCE(status,'active') <> 'inactive'
  ) THEN RAISE EXCEPTION 'Patient does not exist or is inactive'; END IF;
  INSERT INTO public.encounters (patient_id, symptoms, clerking_notes, practitioner_id, status)
  VALUES (_patient_id, NULLIF(trim(_symptoms), ''), NULLIF(trim(_clerking_notes), ''), auth.uid(), 'draft')
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_patient_vitals(
  _patient_id UUID, _temperature NUMERIC DEFAULT NULL, _pulse NUMERIC DEFAULT NULL,
  _systolic NUMERIC DEFAULT NULL, _diastolic NUMERIC DEFAULT NULL,
  _respiratory_rate NUMERIC DEFAULT NULL, _oxygen_saturation NUMERIC DEFAULT NULL,
  _weight_kg NUMERIC DEFAULT NULL, _height_cm NUMERIC DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR
    public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')
  ) THEN RAISE EXCEPTION 'Vital recording is not permitted'; END IF;
  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id AND COALESCE(status,'active') <> 'inactive'
  ) THEN RAISE EXCEPTION 'Patient does not exist or is inactive'; END IF;
  INSERT INTO public.vital_signs(patient_id,temperature,pulse,systolic,diastolic,respiratory_rate,oxygen_saturation,weight_kg,height_cm,recorded_by)
  VALUES (_patient_id,_temperature,_pulse,_systolic,_diastolic,_respiratory_rate,_oxygen_saturation,_weight_kg,_height_cm,auth.uid())
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('vital_id',v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_patient_lab_order(
  _patient_id UUID, _test_name TEXT, _clinical_notes TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR
    public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')
  ) THEN RAISE EXCEPTION 'Laboratory order creation is not permitted'; END IF;
  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id AND COALESCE(status,'active') <> 'inactive'
  ) THEN RAISE EXCEPTION 'Patient does not exist or is inactive'; END IF;
  IF NULLIF(btrim(_test_name),'') IS NULL THEN RAISE EXCEPTION 'Test name is required'; END IF;
  INSERT INTO public.lab_orders(patient_id,test_name,clinical_notes,status)
  VALUES (_patient_id,btrim(_test_name),NULLIF(btrim(_clinical_notes),''),'pending_payment_approval')
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('lab_order_id',v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_patient_document(
  _patient_id UUID, _document_type TEXT, _file_url TEXT, _notes TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR
    public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR
    public.has_role(auth.uid(),'front_desk')
  ) THEN RAISE EXCEPTION 'Document creation is not permitted'; END IF;
  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id AND COALESCE(status,'active') <> 'inactive'
  ) THEN RAISE EXCEPTION 'Patient does not exist or is inactive'; END IF;
  IF NULLIF(btrim(_document_type),'') IS NULL OR NULLIF(btrim(_file_url),'') IS NULL THEN
    RAISE EXCEPTION 'Document type and file URL are required';
  END IF;
  INSERT INTO public.patient_documents(patient_id,document_type,file_url,notes,uploaded_by)
  VALUES (_patient_id,btrim(_document_type),btrim(_file_url),NULLIF(btrim(_notes),''),auth.uid())
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('document_id',v_id);
END;
$$;

REVOKE ALL ON FUNCTION public.create_encounter_workflow(UUID,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.record_patient_vitals(UUID,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_patient_lab_order(UUID,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_patient_document(UUID,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_workflow(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_patient_vitals(UUID,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_lab_order(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_document(UUID,TEXT,TEXT,TEXT) TO authenticated;
