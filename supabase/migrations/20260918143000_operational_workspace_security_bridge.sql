-- Secure role-scoped operational read bridge. Direct protected table reads remain denied.
CREATE OR REPLACE FUNCTION public.get_operational_workspace(_module text, _limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_limit integer := greatest(1, least(coalesce(_limit,200),500));
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT role::text INTO v_role FROM public.profiles WHERE id=auth.uid();
  IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;

  IF _module='appointments' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse','front_desk') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('appointments',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,patient_id,scheduled_at,reason,status,department,attending_officer_id,treatment_status,treatment_notes FROM public.appointments ORDER BY scheduled_at ASC LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='ward' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('wards',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,name,code,specialty,gender_policy,active FROM public.ward_units WHERE active=true ORDER BY name LIMIT v_limit)x),'[]'::jsonb),'beds',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,ward_id,bed_number,status,patient_id,admission_id FROM public.ward_beds ORDER BY bed_number LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='handover' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('handovers',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,patient_id,shift_label,clinical_summary,pending_tasks,safety_concerns,escalation_required,acknowledged_at,created_at FROM public.nursing_shift_handovers ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='nursing_care' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('care_plans',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,patient_id,problem,goal,interventions,priority,status,created_at,updated_at FROM public.nursing_care_plans ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='theatre' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('cases',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,patient_id,procedure_name,theatre_name,scheduled_start,urgency,status,anesthetist_id FROM public.theatre_cases ORDER BY scheduled_start ASC LIMIT v_limit)x),'[]'::jsonb),'profiles',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,full_name,specialization FROM public.profiles WHERE role::text IN ('practitioner','nurse','specialist_nurse') ORDER BY full_name LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='transfusion' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('records',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,patient_id,blood_product,unit_identifier,blood_group,status,reaction_observed,reaction_notes FROM public.transfusion_records ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='insurance' THEN
    IF v_role NOT IN ('admin','accountant') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('claims',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,patient_id,payer_name,member_number,claim_number,amount_claimed,amount_approved,amount_paid,status,rejection_reason,service_from,service_to,created_at FROM public.insurance_claims ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='medication_administration' THEN
    IF v_role NOT IN ('admin','nurse','specialist_nurse','midwife','practitioner') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('records',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,patient_id,medication_name,dose,route,scheduled_at,administered_at,administered_by,status,reason,notes,locked_at,lock_reason,due_window_minutes,reopened_at,reopen_reason FROM public.medication_administrations ORDER BY scheduled_at DESC NULLS LAST LIMIT v_limit)x),'[]'::jsonb),'profiles',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,first_name,last_name,department FROM public.profiles LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='ai_clinical' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse','radiologist') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('sessions',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,specialist,status,review_status,created_at,model_provider,model_name FROM public.ai_clinical_sessions ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='data_migration' THEN
    IF v_role<>'admin' THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('batches',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,entity_type,source_system,source_version,file_name,total_rows,staged_rows,accepted_rows,rejected_rows,status,created_at,approved_at,completed_at FROM public.data_migration_batches WHERE entity_type='legacy_clinical_records' ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb));
  ELSIF _module='facilities' THEN
    IF v_role NOT IN ('admin','front_desk','accountant') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    RETURN jsonb_build_object('facilities',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,name,facility_code,facility_type,district,region,dhims2_uid,is_active FROM public.healthcare_facilities WHERE is_active=true ORDER BY name LIMIT v_limit)x),'[]'::jsonb));
  ELSE RAISE EXCEPTION 'Unsupported workspace module';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.get_operational_workspace(text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_operational_workspace(text,integer) TO authenticated;
