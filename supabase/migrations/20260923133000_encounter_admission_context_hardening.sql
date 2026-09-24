-- Harden encounter prescription/diagnosis and admission workflow context.
CREATE OR REPLACE FUNCTION public.create_encounter_prescription(_encounter_id UUID,_medication TEXT,_dosage TEXT DEFAULT NULL,_frequency TEXT DEFAULT NULL,_duration TEXT DEFAULT NULL)
RETURNS public.prescriptions LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.prescriptions; patient_id_value UUID; encounter_status TEXT;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to prescribe'; END IF;
 SELECT patient_id,status INTO patient_id_value,encounter_status FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF patient_id_value IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=patient_id_value AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient does not exist or is inactive'; END IF;
 IF encounter_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
 IF NULLIF(trim(_medication),'') IS NULL THEN RAISE EXCEPTION 'Medication is required'; END IF;
 INSERT INTO public.prescriptions(encounter_id,patient_id,prescribed_by,medication,dosage,frequency,duration)
 VALUES(_encounter_id,patient_id_value,auth.uid(),trim(_medication),NULLIF(trim(_dosage),''),NULLIF(trim(_frequency),''),NULLIF(trim(_duration),''))
 RETURNING * INTO result;
 RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.set_principal_diagnosis(_encounter_id UUID,_diagnosis_id UUID)
RETURNS public.diagnoses LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.diagnoses; encounter_status TEXT;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to set principal diagnosis'; END IF;
 SELECT status INTO encounter_status FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF encounter_status IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 IF encounter_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.diagnoses WHERE id=_diagnosis_id AND encounter_id=_encounter_id) THEN RAISE EXCEPTION 'Diagnosis does not belong to encounter'; END IF;
 UPDATE public.diagnoses SET is_principal=false WHERE encounter_id=_encounter_id;
 UPDATE public.diagnoses SET is_principal=true WHERE id=_diagnosis_id RETURNING * INTO result;
 UPDATE public.encounters SET principal_diagnosis=result.diagnosis,updated_at=now() WHERE id=_encounter_id;
 RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.create_admission_workflow(_patient_id UUID,_ward TEXT,_bed TEXT DEFAULT NULL,_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Admission creation is not permitted'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF NULLIF(btrim(_ward),'') IS NULL THEN RAISE EXCEPTION 'Ward is required'; END IF;
 INSERT INTO public.admissions(patient_id,ward,bed,reason,admitted_by,status,admitted_at)
 VALUES(_patient_id,btrim(_ward),NULLIF(btrim(_bed),''),NULLIF(btrim(_reason),''),auth.uid(),'admitted',now())
 RETURNING id INTO v_id;
 RETURN jsonb_build_object('admission_id',v_id,'status','admitted');
END; $$;

CREATE OR REPLACE FUNCTION public.discharge_admission_workflow(_admission_id UUID,_summary TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Admission discharge is not permitted'; END IF;
 UPDATE public.admissions SET status='discharged',discharged_at=now(),discharge_summary=COALESCE(NULLIF(btrim(_summary),''),'Discharged from inpatient admission.')
 WHERE id=_admission_id AND status='admitted' AND EXISTS(SELECT 1 FROM public.patients p WHERE p.id=admissions.patient_id AND COALESCE(p.status,'active')<>'inactive')
 RETURNING id INTO v_id;
 IF v_id IS NULL THEN RAISE EXCEPTION 'Admission not found, inactive, or no longer active'; END IF;
 RETURN jsonb_build_object('admission_id',v_id,'status','discharged');
END; $$;

REVOKE ALL ON FUNCTION public.create_encounter_prescription(UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.set_principal_diagnosis(UUID,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_prescription(UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_principal_diagnosis(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) TO authenticated;
