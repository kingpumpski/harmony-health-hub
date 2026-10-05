CREATE OR REPLACE FUNCTION public.create_care_transition_workflow(_patient_id uuid,_transition_type text,_destination text DEFAULT NULL,_summary text DEFAULT NULL,_medications_reconciled boolean DEFAULT false,_follow_up_required boolean DEFAULT false,_follow_up_date date DEFAULT NULL,_instructions text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_id uuid; pf uuid; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Care transition creation is not permitted'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF _transition_type NOT IN('discharge','transfer','follow_up') THEN RAISE EXCEPTION 'Invalid transition type'; END IF;
 IF _follow_up_required AND _follow_up_date IS NULL THEN RAISE EXCEPTION 'Follow-up date is required when follow-up is required'; END IF;
 INSERT INTO public.care_transitions(patient_id,transition_type,status,destination,summary,medications_reconciled,follow_up_required,follow_up_date,instructions,responsible_officer,facility_id)
 VALUES(_patient_id,_transition_type,'planned',NULLIF(pg_catalog.btrim(_destination),''),NULLIF(pg_catalog.btrim(_summary),''),_medications_reconciled,_follow_up_required,_follow_up_date,NULLIF(pg_catalog.btrim(_instructions),''),uid,pf) RETURNING id INTO v_id;
 PERFORM public.record_system_audit('care_transition_created','care_transitions','care_transition',v_id,'info',jsonb_build_object('patient_id',_patient_id,'transition_type',_transition_type,'facility_id',pf));
 RETURN jsonb_build_object('transition_id',v_id,'status','planned');
END;$function$;
REVOKE ALL ON FUNCTION public.create_care_transition_workflow(uuid,text,text,text,boolean,boolean,date,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_care_transition_workflow(uuid,text,text,text,boolean,boolean,date,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_care_transition_workflow(uuid,text,text,text,boolean,boolean,date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.create_nursing_shift_handover(_patient_id uuid,_shift_label text,_clinical_summary text,_pending_tasks text DEFAULT NULL,_safety_concerns text DEFAULT NULL,_escalation_required boolean DEFAULT false,_ward_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); id uuid; pf uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF NULLIF(pg_catalog.btrim(_clinical_summary),'') IS NULL THEN RAISE EXCEPTION 'Clinical summary is required'; END IF;
 IF _ward_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.ward_units WHERE id=_ward_id AND facility_id=pf) THEN RAISE EXCEPTION 'Ward not found in patient facility'; END IF;
 IF EXISTS(SELECT 1 FROM public.nursing_shift_handovers WHERE patient_id=_patient_id AND facility_id=pf AND shift_label=COALESCE(NULLIF(pg_catalog.btrim(_shift_label),''),'unspecified') AND acknowledged_at IS NULL) THEN RAISE EXCEPTION 'An open handover already exists for this patient and shift'; END IF;
 INSERT INTO public.nursing_shift_handovers(patient_id,facility_id,ward_id,outgoing_officer,shift_label,clinical_summary,pending_tasks,safety_concerns,escalation_required)
 VALUES(_patient_id,pf,_ward_id,uid,COALESCE(NULLIF(pg_catalog.btrim(_shift_label),''),'unspecified'),pg_catalog.btrim(_clinical_summary),NULLIF(pg_catalog.btrim(_pending_tasks),''),NULLIF(pg_catalog.btrim(_safety_concerns),''),COALESCE(_escalation_required,false)) RETURNING id INTO id;
 RETURN id;
END;$function$;
REVOKE ALL ON FUNCTION public.create_nursing_shift_handover(uuid,text,text,text,text,boolean,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_nursing_shift_handover(uuid,text,text,text,text,boolean,uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_nursing_shift_handover(uuid,text,text,text,text,boolean,uuid) TO authenticated;
ALTER FUNCTION public.approve_lab_result(uuid) SET search_path = '';
REVOKE ALL ON FUNCTION public.approve_lab_result(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_lab_result(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(uuid) TO authenticated;