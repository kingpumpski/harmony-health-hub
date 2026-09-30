-- Harden administrator facility reconciliation with strict existence/immutability checks and the canonical audit signature.
CREATE OR REPLACE FUNCTION public.reconcile_remaining_clinical_facility_record(_entity_type text,_entity_id uuid,_target_facility_id uuid,_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_exists boolean:=false; v_patient uuid; v_parent uuid; v_current uuid;
BEGIN
 IF NOT (public.current_user_has_role('admin'::public.app_role) OR public.current_user_has_role('it_admin'::public.app_role)) THEN RAISE EXCEPTION 'Administrator access required'; END IF;
 IF _reason IS NULL OR length(trim(_reason))<5 THEN RAISE EXCEPTION 'Evidence/reason is required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.healthcare_facilities f WHERE f.id=_target_facility_id AND f.is_active) THEN RAISE EXCEPTION 'Target facility is not active'; END IF;
 IF _entity_type='wards' THEN SELECT true,facility_id INTO v_exists,v_current FROM public.wards WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='beds' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.beds WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='anesthetic_assessments' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.anesthetic_assessments WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='billing_overrides' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.billing_overrides WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='dental_records' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.dental_records WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='inpatient_reviews' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.inpatient_reviews WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='meal_orders' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.meal_orders WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='meal_plans' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.meal_plans WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='ophthalmology_exams' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.ophthalmology_exams WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='outside_lab_documents' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.outside_lab_documents WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='patient_account_credits' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.patient_account_credits WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='patient_visit_authorizations' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.patient_visit_authorizations WHERE id=_entity_id FOR UPDATE;
 ELSIF _entity_type='video_sessions' THEN SELECT true,facility_id,patient_id INTO v_exists,v_current,v_patient FROM public.video_sessions WHERE id=_entity_id FOR UPDATE;
 ELSE RAISE EXCEPTION 'Unsupported facility reconciliation entity'; END IF;
 IF NOT v_exists THEN RAISE EXCEPTION 'Facility reconciliation record does not exist'; END IF;
 IF v_current IS NOT NULL THEN RAISE EXCEPTION 'Facility attribution already exists; review is required before changing it'; END IF;
 IF v_patient IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.patients WHERE id=v_patient; IF v_parent IS NOT NULL AND v_parent IS DISTINCT FROM _target_facility_id THEN RAISE EXCEPTION 'Patient facility conflicts with target facility'; END IF; END IF;
 PERFORM set_config('hms.facility_reconciliation','on',true);
 CASE _entity_type
 WHEN 'wards' THEN UPDATE public.wards SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'beds' THEN UPDATE public.beds SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'anesthetic_assessments' THEN UPDATE public.anesthetic_assessments SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'billing_overrides' THEN UPDATE public.billing_overrides SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'dental_records' THEN UPDATE public.dental_records SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'inpatient_reviews' THEN UPDATE public.inpatient_reviews SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'meal_orders' THEN UPDATE public.meal_orders SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'meal_plans' THEN UPDATE public.meal_plans SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'ophthalmology_exams' THEN UPDATE public.ophthalmology_exams SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'outside_lab_documents' THEN UPDATE public.outside_lab_documents SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'patient_account_credits' THEN UPDATE public.patient_account_credits SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'patient_visit_authorizations' THEN UPDATE public.patient_visit_authorizations SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 WHEN 'video_sessions' THEN UPDATE public.video_sessions SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 END CASE;
 PERFORM public.record_system_audit('facility_reconciliation','administration',_entity_type,_entity_id,'info',jsonb_build_object('target_facility_id',_target_facility_id,'reason',trim(_reason)));
END $$;
REVOKE ALL ON FUNCTION public.reconcile_remaining_clinical_facility_record(text,uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reconcile_remaining_clinical_facility_record(text,uuid,uuid,text) TO authenticated;