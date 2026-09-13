CREATE OR REPLACE FUNCTION public.create_patient_referral_workflow(
  _patient_id UUID, _destination TEXT, _specialty TEXT DEFAULT NULL, _reason TEXT DEFAULT NULL,
  _urgency TEXT DEFAULT 'routine', _clinical_summary TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR has_role(auth.uid(),'specialist_nurse') OR has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Referral creation is not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF NULLIF(btrim(_destination),'') IS NULL OR NULLIF(btrim(_reason),'') IS NULL THEN RAISE EXCEPTION 'Destination and reason are required'; END IF;
  IF _urgency NOT IN ('routine','urgent','emergency') THEN RAISE EXCEPTION 'Invalid referral urgency'; END IF;
  INSERT INTO patient_referrals(patient_id,destination,specialty,reason,urgency,clinical_summary,referred_by)
  VALUES(_patient_id,btrim(_destination),NULLIF(btrim(_specialty),''),btrim(_reason),_urgency,NULLIF(btrim(_clinical_summary),''),auth.uid()) RETURNING id INTO v_id;
  PERFORM record_system_audit('referral_created','care_transitions','patient_referral',v_id,'info',jsonb_build_object('patient_id',_patient_id,'urgency',_urgency));
  RETURN jsonb_build_object('referral_id',v_id,'status','requested');
END; $$;

CREATE OR REPLACE FUNCTION public.create_care_transition_workflow(
  _patient_id UUID, _transition_type TEXT, _destination TEXT DEFAULT NULL, _summary TEXT DEFAULT NULL,
  _medications_reconciled BOOLEAN DEFAULT false, _follow_up_required BOOLEAN DEFAULT false,
  _follow_up_date DATE DEFAULT NULL, _instructions TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Care transition creation is not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF _transition_type NOT IN ('discharge','transfer','follow_up') THEN RAISE EXCEPTION 'Invalid transition type'; END IF;
  IF _follow_up_required AND _follow_up_date IS NULL THEN RAISE EXCEPTION 'Follow-up date is required when follow-up is required'; END IF;
  INSERT INTO care_transitions(patient_id,transition_type,status,destination,summary,medications_reconciled,follow_up_required,follow_up_date,instructions,responsible_officer)
  VALUES(_patient_id,_transition_type,'planned',NULLIF(btrim(_destination),''),NULLIF(btrim(_summary),''),_medications_reconciled,_follow_up_required,_follow_up_date,NULLIF(btrim(_instructions),''),auth.uid()) RETURNING id INTO v_id;
  PERFORM record_system_audit('care_transition_created','care_transitions','care_transition',v_id,'info',jsonb_build_object('patient_id',_patient_id,'transition_type',_transition_type));
  RETURN jsonb_build_object('transition_id',v_id,'status','planned');
END; $$;

REVOKE ALL ON FUNCTION public.create_patient_referral_workflow(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_care_transition_workflow(UUID,TEXT,TEXT,TEXT,BOOLEAN,BOOLEAN,DATE,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_patient_referral_workflow(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_care_transition_workflow(UUID,TEXT,TEXT,TEXT,BOOLEAN,BOOLEAN,DATE,TEXT) TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.patient_referrals FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.care_transitions FROM authenticated;
GRANT SELECT ON public.patient_referrals TO authenticated;
GRANT SELECT ON public.care_transitions TO authenticated;
