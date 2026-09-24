-- Strengthen emergency, theatre, transfusion and inpatient bed patient context.
CREATE OR REPLACE FUNCTION public.create_emergency_case(_patient_id UUID,_chief_complaint TEXT,_acuity TEXT DEFAULT 'urgent',_arrival_mode TEXT DEFAULT 'walk_in',_assigned_officer UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); v_id UUID; v_assigned UUID;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Emergency workflow role required'; END IF;
 IF _patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF NULLIF(trim(_chief_complaint),'') IS NULL THEN RAISE EXCEPTION 'Chief complaint is required'; END IF;
 IF _acuity NOT IN ('resuscitation','emergency','urgent','less_urgent','non_urgent') THEN RAISE EXCEPTION 'Invalid emergency acuity'; END IF;
 IF _arrival_mode NOT IN ('walk_in','ambulance','referral','other') THEN RAISE EXCEPTION 'Invalid arrival mode'; END IF;
 IF _assigned_officer IS NOT NULL AND _assigned_officer<>uid AND NOT public.has_role(uid,'admin') THEN RAISE EXCEPTION 'Only an administrator may assign another officer during creation'; END IF;
 v_assigned:=COALESCE(_assigned_officer,uid);
 INSERT INTO public.emergency_cases(patient_id,arrival_mode,acuity,chief_complaint,assigned_officer,status)
 VALUES(_patient_id,_arrival_mode,_acuity,trim(_chief_complaint),v_assigned,'waiting') RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_theatre_case(_patient_id uuid,_procedure_name text,_scheduled_start timestamptz DEFAULT NULL,_theatre_name text DEFAULT NULL,_urgency text DEFAULT 'elective',_surgeon_id uuid DEFAULT NULL,_anesthetist_id uuid DEFAULT NULL,_encounter_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid; v_patient uuid; v_status text;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Not authorized to create theatre cases'; END IF;
 IF _patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF NULLIF(trim(_procedure_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and procedure are required'; END IF;
 IF _encounter_id IS NOT NULL THEN
  SELECT patient_id,status INTO v_patient,v_status FROM public.encounters WHERE id=_encounter_id;
  IF NOT FOUND OR v_patient<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to the selected patient'; END IF;
  IF v_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot create a theatre case for a completed or cancelled encounter'; END IF;
 END IF;
 INSERT INTO public.theatre_cases(patient_id,procedure_name,surgeon_id,anaesthetist_id,scheduled_at,theatre,status,created_by,encounter_id)
 VALUES(_patient_id,trim(_procedure_name),_surgeon_id,_anesthetist_id,_scheduled_start,NULLIF(trim(COALESCE(_theatre_name,'')),''),COALESCE(NULLIF(trim(_urgency),''),'elective'),auth.uid(),_encounter_id)
 RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_transfusion_record(_patient_id uuid,_blood_product text,_unit_identifier text,_blood_group text DEFAULT NULL,_consent_confirmed boolean DEFAULT false,_encounter_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid; v_patient uuid; v_status text;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Not authorized to create transfusion records'; END IF;
 IF _patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF NULLIF(trim(_blood_product),'') IS NULL THEN RAISE EXCEPTION 'Patient and blood product are required'; END IF;
 IF _consent_confirmed IS NOT TRUE THEN RAISE EXCEPTION 'Documented transfusion consent must be confirmed before scheduling'; END IF;
 IF _encounter_id IS NOT NULL THEN
  SELECT patient_id,status INTO v_patient,v_status FROM public.encounters WHERE id=_encounter_id;
  IF NOT FOUND OR v_patient<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to the selected patient'; END IF;
  IF v_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot schedule transfusion for a completed or cancelled encounter'; END IF;
 END IF;
 INSERT INTO public.transfusion_records(patient_id,blood_group,component,unit_identifier,consent_confirmed,status,encounter_id)
 VALUES(_patient_id,NULLIF(trim(COALESCE(_blood_group,'')),''),trim(_blood_product),NULLIF(trim(COALESCE(_unit_identifier,'')),''),true,'issued',_encounter_id)
 RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.assign_ward_bed(_bed_id UUID,_patient_id UUID,_admission_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b public.ward_beds%ROWTYPE; uid UUID:=auth.uid(); admission_patient UUID;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
 IF _patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 SELECT * INTO b FROM public.ward_beds WHERE id=_bed_id FOR UPDATE;
 IF b.id IS NULL THEN RAISE EXCEPTION 'Bed not found'; END IF;
 IF b.status<>'available' OR b.patient_id IS NOT NULL THEN RAISE EXCEPTION 'Bed is not available'; END IF;
 IF _admission_id IS NOT NULL THEN
  SELECT patient_id INTO admission_patient FROM public.admissions WHERE id=_admission_id;
  IF NOT FOUND OR admission_patient<>_patient_id THEN RAISE EXCEPTION 'Admission does not belong to patient'; END IF;
 END IF;
 UPDATE public.ward_beds SET patient_id=_patient_id,admission_id=_admission_id,status='occupied',occupied_at=now(),released_at=NULL WHERE id=_bed_id;
 PERFORM public.record_system_audit('ward_bed_assigned','inpatient','ward_bed',_bed_id,'info',jsonb_build_object('patient_id',_patient_id,'admission_id',_admission_id));
 RETURN jsonb_build_object('bed_id',_bed_id,'status','occupied','patient_id',_patient_id);
END; $$;

REVOKE ALL ON FUNCTION public.create_emergency_case(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.assign_ward_bed(UUID,UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_emergency_case(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_ward_bed(UUID,UUID,UUID) TO authenticated;
