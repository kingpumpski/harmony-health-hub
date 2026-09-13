-- Secure the legacy admissions UI behind explicit workflow RPCs.
CREATE OR REPLACE FUNCTION public.create_admission_workflow(_patient_id UUID, _ward TEXT, _bed TEXT DEFAULT NULL, _reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Admission creation is not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF _ward IS NULL OR btrim(_ward)='' THEN RAISE EXCEPTION 'Ward is required'; END IF;
  INSERT INTO admissions(patient_id,ward,bed,reason,admitted_by,status,admitted_at)
  VALUES (_patient_id,btrim(_ward),NULLIF(btrim(_bed),''),NULLIF(btrim(_reason),''),auth.uid(),'admitted',now())
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('admission_id',v_id,'status','admitted');
END; $$;

CREATE OR REPLACE FUNCTION public.discharge_admission_workflow(_admission_id UUID, _summary TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Admission discharge is not permitted'; END IF;
  UPDATE admissions
  SET status='discharged', discharged_at=now(), discharge_summary=COALESCE(NULLIF(btrim(_summary),''),'Discharged from inpatient admission.')
  WHERE id=_admission_id AND status='admitted'
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'Admission not found or is no longer active'; END IF;
  RETURN jsonb_build_object('admission_id',v_id,'status','discharged');
END; $$;

REVOKE ALL ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) TO authenticated;
