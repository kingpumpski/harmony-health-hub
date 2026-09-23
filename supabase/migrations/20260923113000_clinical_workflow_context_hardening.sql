-- Patient-context and lifecycle hardening for remaining clinical SECURITY DEFINER workflows.

CREATE OR REPLACE FUNCTION public.add_encounter_diagnosis(_encounter_id UUID,_diagnosis TEXT,_icd_code TEXT DEFAULT NULL)
RETURNS public.diagnoses LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $
DECLARE v_status text; v_result public.diagnoses;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to add diagnoses'; END IF;
 SELECT status INTO v_status FROM public.encounters WHERE id=_encounter_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 IF v_status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Encounter is closed'; END IF;
 IF NULLIF(trim(_diagnosis),'') IS NULL THEN RAISE EXCEPTION 'Diagnosis is required'; END IF;
 IF _icd_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.icd_codes WHERE code=upper(trim(_icd_code))) THEN RAISE EXCEPTION 'Diagnosis code is not in the approved ICD-10/STG catalogue'; END IF;
 INSERT INTO public.diagnoses(encounter_id,diagnosis,icd_code,is_principal) VALUES(_encounter_id,trim(_diagnosis),NULLIF(upper(trim(_icd_code)),''),false) RETURNING * INTO v_result;
 RETURN v_result;
END; $;

CREATE OR REPLACE FUNCTION public.remove_encounter_diagnosis(_diagnosis_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_encounter uuid; v_status text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to remove diagnoses'; END IF;
 SELECT encounter_id INTO v_encounter FROM public.diagnoses WHERE id=_diagnosis_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Diagnosis does not exist'; END IF;
 SELECT status INTO v_status FROM public.encounters WHERE id=v_encounter;
 IF v_status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Encounter is closed'; END IF;
 DELETE FROM public.diagnoses WHERE id=_diagnosis_id;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_encounter_workflow(_encounter_id UUID)
RETURNS public.encounters LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.encounters;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to complete encounters'; END IF;
 SELECT * INTO result FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 IF result.status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Encounter is already closed'; END IF;
 IF result.principal_diagnosis IS NULL OR NULLIF(trim(result.principal_diagnosis),'') IS NULL THEN RAISE EXCEPTION 'Principal diagnosis required'; END IF;
 UPDATE public.encounters SET status='completed',completed_at=COALESCE(completed_at,now()),updated_at=COALESCE(updated_at,now()) WHERE id=_encounter_id RETURNING * INTO result;
 RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.create_patient_referral_workflow(_patient_id UUID,_destination TEXT,_specialty TEXT DEFAULT NULL,_reason TEXT DEFAULT NULL,_urgency TEXT DEFAULT 'routine',_clinical_summary TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR has_role(auth.uid(),'specialist_nurse') OR has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Referral creation is not permitted'; END IF;
 IF NOT EXISTS (SELECT 1 FROM patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF NULLIF(btrim(_destination),'') IS NULL OR NULLIF(btrim(_reason),'') IS NULL THEN RAISE EXCEPTION 'Destination and reason are required'; END IF;
 IF _urgency NOT IN ('routine','urgent','emergency') THEN RAISE EXCEPTION 'Invalid referral urgency'; END IF;
 INSERT INTO patient_referrals(patient_id,destination,specialty,reason,urgency,clinical_summary,referred_by) VALUES(_patient_id,btrim(_destination),NULLIF(btrim(_specialty),''),btrim(_reason),_urgency,NULLIF(btrim(_clinical_summary),''),auth.uid()) RETURNING id INTO v_id;
 PERFORM record_system_audit('referral_created','care_transitions','patient_referral',v_id,'info',jsonb_build_object('patient_id',_patient_id,'urgency',_urgency));
 RETURN jsonb_build_object('referral_id',v_id,'status','requested');
END; $$;

CREATE OR REPLACE FUNCTION public.create_care_transition_workflow(_patient_id UUID,_transition_type TEXT,_destination TEXT DEFAULT NULL,_summary TEXT DEFAULT NULL,_medications_reconciled BOOLEAN DEFAULT false,_follow_up_required BOOLEAN DEFAULT false,_follow_up_date DATE DEFAULT NULL,_instructions TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Care transition creation is not permitted'; END IF;
 IF NOT EXISTS (SELECT 1 FROM patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF _transition_type NOT IN ('discharge','transfer','follow_up') THEN RAISE EXCEPTION 'Invalid transition type'; END IF;
 IF _follow_up_required AND _follow_up_date IS NULL THEN RAISE EXCEPTION 'Follow-up date is required when follow-up is required'; END IF;
 INSERT INTO care_transitions(patient_id,transition_type,status,destination,summary,medications_reconciled,follow_up_required,follow_up_date,instructions,responsible_officer) VALUES(_patient_id,_transition_type,'planned',NULLIF(btrim(_destination),''),NULLIF(btrim(_summary),''),_medications_reconciled,_follow_up_required,_follow_up_date,NULLIF(btrim(_instructions),''),auth.uid()) RETURNING id INTO v_id;
 PERFORM record_system_audit('care_transition_created','care_transitions','care_transition',v_id,'info',jsonb_build_object('patient_id',_patient_id,'transition_type',_transition_type));
 RETURN jsonb_build_object('transition_id',v_id,'status','planned');
END; $$;

CREATE OR REPLACE FUNCTION public.create_fertility_cycle_workflow(_patient_id UUID,_partner_name TEXT DEFAULT NULL,_cycle_type TEXT DEFAULT 'IVF',_start_date DATE DEFAULT CURRENT_DATE,_protocol TEXT DEFAULT NULL)
RETURNS public.fertility_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cycle public.fertility_cycles; v_cycle_number integer;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Insufficient role for fertility workflow'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF upper(trim(_cycle_type)) NOT IN ('IVF','IUI','ICSI','FET') THEN RAISE EXCEPTION 'Unsupported fertility cycle type'; END IF;
 SELECT COALESCE(MAX(cycle_number),0)+1 INTO v_cycle_number FROM public.fertility_cycles WHERE patient_id=_patient_id;
 INSERT INTO public.fertility_cycles(patient_id,partner_name,cycle_type,cycle_number,start_date,protocol,status,assigned_specialist) VALUES(_patient_id,NULLIF(trim(_partner_name),''),upper(trim(_cycle_type)),v_cycle_number,_start_date,NULLIF(trim(_protocol),''),'active',auth.uid()) RETURNING * INTO v_cycle;
 PERFORM public.record_system_audit('fertility_cycle_created','fertility','fertility_cycle',v_cycle.id,'info',jsonb_build_object('patient_id',_patient_id,'cycle_type',v_cycle.cycle_type));
 RETURN v_cycle;
END; $$;

CREATE OR REPLACE FUNCTION public.record_fertility_monitoring_workflow(_cycle_id UUID,_visit_date DATE,_cycle_day INTEGER DEFAULT NULL,_estradiol NUMERIC DEFAULT NULL,_lh NUMERIC DEFAULT NULL,_fsh NUMERIC DEFAULT NULL,_progesterone NUMERIC DEFAULT NULL,_follicle_count_left INTEGER DEFAULT NULL,_follicle_count_right INTEGER DEFAULT NULL,_endometrial_thickness NUMERIC DEFAULT NULL,_medication_adjustments TEXT DEFAULT NULL)
RETURNS public.fertility_monitoring LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_row public.fertility_monitoring; v_patient uuid; v_status text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Insufficient role for fertility workflow'; END IF;
 SELECT patient_id,status INTO v_patient,v_status FROM public.fertility_cycles WHERE id=_cycle_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Fertility cycle not found'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=v_patient AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF v_status IN ('completed','cancelled','successful','unsuccessful') THEN RAISE EXCEPTION 'Fertility cycle is closed'; END IF;
 IF _visit_date IS NULL THEN RAISE EXCEPTION 'Visit date is required'; END IF;
 IF _cycle_day IS NOT NULL AND _cycle_day<1 THEN RAISE EXCEPTION 'Cycle day must be positive'; END IF;
 IF _follicle_count_left IS NOT NULL AND _follicle_count_left<0 THEN RAISE EXCEPTION 'Left follicle count cannot be negative'; END IF;
 IF _follicle_count_right IS NOT NULL AND _follicle_count_right<0 THEN RAISE EXCEPTION 'Right follicle count cannot be negative'; END IF;
 IF _endometrial_thickness IS NOT NULL AND _endometrial_thickness<0 THEN RAISE EXCEPTION 'Endometrial thickness cannot be negative'; END IF;
 INSERT INTO public.fertility_monitoring(cycle_id,visit_date,cycle_day,estradiol,lh,fsh,progesterone,follicle_count_left,follicle_count_right,endometrial_thickness,medication_adjustments,recorded_by) VALUES(_cycle_id,_visit_date,_cycle_day,_estradiol,_lh,_fsh,_progesterone,_follicle_count_left,_follicle_count_right,_endometrial_thickness,NULLIF(trim(_medication_adjustments),''),auth.uid()) RETURNING * INTO v_row;
 PERFORM public.record_system_audit('fertility_monitoring_recorded','fertility','fertility_monitoring',v_row.id,'info',jsonb_build_object('cycle_id',_cycle_id,'visit_date',_visit_date));
 RETURN v_row;
END; $$;

CREATE OR REPLACE FUNCTION public.transition_fertility_cycle_workflow(_cycle_id UUID,_status TEXT,_outcome TEXT DEFAULT NULL)
RETURNS public.fertility_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cycle public.fertility_cycles; v_patient uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Insufficient role for fertility workflow'; END IF;
 IF lower(trim(_status)) NOT IN ('active','completed','cancelled','successful','unsuccessful') THEN RAISE EXCEPTION 'Unsupported fertility cycle status'; END IF;
 SELECT patient_id INTO v_patient FROM public.fertility_cycles WHERE id=_cycle_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Fertility cycle not found'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=v_patient AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 UPDATE public.fertility_cycles SET status=lower(trim(_status)),outcome=NULLIF(trim(_outcome),''),updated_at=now() WHERE id=_cycle_id RETURNING * INTO v_cycle;
 PERFORM public.record_system_audit('fertility_cycle_transitioned','fertility','fertility_cycle',v_cycle.id,'info',jsonb_build_object('status',v_cycle.status,'outcome',v_cycle.outcome));
 RETURN v_cycle;
END; $$;

CREATE OR REPLACE FUNCTION public.create_dental_record(_patient_id UUID,_examination TEXT,_treatment_plan TEXT,_procedures_performed TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _id uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'dentist')) THEN RAISE EXCEPTION 'Dental clinical role required'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 INSERT INTO public.dental_records(patient_id,examination,treatment_plan,procedures_performed,performed_by) VALUES(_patient_id,NULLIF(trim(_examination),''),NULLIF(trim(_treatment_plan),''),NULLIF(trim(_procedures_performed),''),auth.uid()) RETURNING id INTO _id;
 RETURN _id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_procedure_note(_patient_id UUID,_procedure_name TEXT,_template_used TEXT,_indication TEXT,_technique TEXT,_findings TEXT,_complications TEXT,_post_op_plan TEXT,_charge_amount NUMERIC,_service_order_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); sid public.service_orders%ROWTYPE; id UUID;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF COALESCE(_charge_amount,0)<0 THEN RAISE EXCEPTION 'Charge amount cannot be negative'; END IF;
 IF COALESCE(_charge_amount,0)>0 THEN
   IF _service_order_id IS NULL THEN RAISE EXCEPTION 'A released service order is required for a chargeable procedure'; END IF;
   SELECT * INTO sid FROM public.service_orders WHERE id=_service_order_id FOR UPDATE;
   IF NOT FOUND OR sid.patient_id<>_patient_id OR sid.department<>'procedure' OR (sid.related_entity_id IS NOT NULL AND sid.related_entity_id<>_service_order_id) THEN RAISE EXCEPTION 'Procedure service order linkage is invalid'; END IF;
   IF sid.status NOT IN('released','in_progress','completed') THEN RAISE EXCEPTION 'Procedure payment has not been released'; END IF;
 END IF;
 INSERT INTO public.procedure_notes(patient_id,procedure_name,template_used,indication,technique,findings,complications,post_op_plan,performed_by,status,charge_amount,service_order_id)
 VALUES(_patient_id,NULLIF(btrim(_procedure_name),''),NULLIF(btrim(_template_used),''),NULLIF(btrim(_indication),''),NULLIF(btrim(_technique),''),NULLIF(btrim(_findings),''),NULLIF(btrim(_complications),''),NULLIF(btrim(_post_op_plan),''),uid,'completed',COALESCE(_charge_amount,0),_service_order_id)
 RETURNING id INTO id;
 RETURN id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_pharmacy_pos_sale(_patient_id uuid,_inventory_id uuid,_quantity integer)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory; order_id uuid; patient_uuid uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Pharmacy or front desk role required'; END IF;
 IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 IF _patient_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 SELECT * INTO item FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE;
 IF NOT FOUND OR NOT item.active OR item.stock_quantity<_quantity THEN RAISE EXCEPTION 'Insufficient or unavailable stock'; END IF;
 patient_uuid:=_patient_id;
 IF patient_uuid IS NULL THEN INSERT INTO public.patients(patient_code,first_name,last_name,status,created_by) VALUES(NULL,'Walk-in','Pharmacy','active',auth.uid()) RETURNING id INTO patient_uuid; END IF;
 INSERT INTO public.pharmacy_pos_sales(patient_id,medication,inventory_id,quantity,unit_price,created_by) VALUES(patient_uuid,item.drug_name,item.id,_quantity,COALESCE(item.unit_price,0),auth.uid()) RETURNING * INTO result;
 INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes) VALUES(patient_uuid,'pharmacy','Walk-in: '||item.drug_name,COALESCE(item.unit_price,0)*_quantity,result.id,'pending_payment_approval',auth.uid(),'drug',item.id,'POS sale '||result.id::text) RETURNING id INTO order_id;
 UPDATE public.pharmacy_pos_sales SET service_order_id=order_id WHERE id=result.id RETURNING * INTO result;
 RETURN result;
END; $$;

REVOKE ALL ON FUNCTION public.add_encounter_diagnosis(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_encounter_diagnosis(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_encounter_workflow(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_patient_referral_workflow(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_care_transition_workflow(UUID,TEXT,TEXT,TEXT,BOOLEAN,BOOLEAN,DATE,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_fertility_cycle_workflow(UUID,TEXT,TEXT,DATE,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_fertility_monitoring_workflow(UUID,DATE,INTEGER,NUMERIC,NUMERIC,NUMERIC,NUMERIC,INTEGER,INTEGER,NUMERIC,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transition_fertility_cycle_workflow(UUID,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_dental_record(UUID,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_procedure_note(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_pharmacy_pos_sale(UUID,UUID,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_encounter_diagnosis(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_encounter_diagnosis(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_encounter_workflow(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_referral_workflow(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_care_transition_workflow(UUID,TEXT,TEXT,TEXT,BOOLEAN,BOOLEAN,DATE,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_fertility_cycle_workflow(UUID,TEXT,TEXT,DATE,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_fertility_monitoring_workflow(UUID,DATE,INTEGER,NUMERIC,NUMERIC,NUMERIC,NUMERIC,INTEGER,INTEGER,NUMERIC,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_fertility_cycle_workflow(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_dental_record(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_procedure_note(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_pos_sale(UUID,UUID,INTEGER) TO authenticated;
