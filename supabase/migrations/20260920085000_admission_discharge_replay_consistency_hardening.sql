-- Harden inpatient admission/discharge transitions against replay and cross-record races.
CREATE OR REPLACE FUNCTION public.admit_encounter_workflow(
  _encounter_id UUID,_reason TEXT DEFAULT NULL,_ward TEXT DEFAULT NULL,_emergency_override BOOLEAN DEFAULT TRUE
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
 v_enc public.encounters%ROWTYPE; v_admission UUID; v_override BOOLEAN:=FALSE; v_order RECORD;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Admission is not permitted for this role'; END IF;
 SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=v_enc.patient_id) THEN RAISE EXCEPTION 'Encounter patient not found'; END IF;
 IF v_enc.status='cancelled' THEN RAISE EXCEPTION 'Cancelled encounters cannot be admitted'; END IF;
 IF v_enc.admission_id IS NOT NULL THEN
   RETURN jsonb_build_object('admission_id',v_enc.admission_id,'override',FALSE,'existing',TRUE);
 END IF;
 SELECT COALESCE(allow_treatment_before_deposit,FALSE) AND COALESCE(admission_financial_override_enabled,FALSE) AND COALESCE(allow_clinical_emergency_override,FALSE)
 INTO v_override FROM public.facility_configuration WHERE id='default' LIMIT 1;
 v_override:=COALESCE(v_override,FALSE) AND COALESCE(_emergency_override,TRUE);
 INSERT INTO public.admissions(patient_id,encounter_id,ward,reason,admitted_by,status)
 VALUES(v_enc.patient_id,v_enc.id,NULLIF(btrim(_ward),''),COALESCE(NULLIF(btrim(_reason),''),'Clinical admission'),auth.uid(),'admitted')
 RETURNING id INTO v_admission;
 UPDATE public.encounters SET admission_id=v_admission,updated_at=now() WHERE id=v_enc.id;
 IF v_override THEN
   FOR v_order IN SELECT * FROM public.service_orders WHERE encounter_id=v_enc.id AND status='pending_payment_approval' FOR UPDATE LOOP
     INSERT INTO public.billing_overrides(service_order_id,patient_id,department,related_entity_id,reason,overridden_by,approved_by,approved_at)
     VALUES(v_order.id,v_order.patient_id,v_order.department,v_order.related_entity_id,COALESCE(NULLIF(btrim(_reason),''),'Emergency treatment before deposit'),auth.uid(),auth.uid(),now())
     ON CONFLICT(service_order_id) DO UPDATE SET reason=EXCLUDED.reason,overridden_by=EXCLUDED.overridden_by,approved_by=EXCLUDED.approved_by,approved_at=EXCLUDED.approved_at;
     UPDATE public.service_orders SET status='released',approved_at=now(),approved_by=auth.uid(),released_at=now(),released_by=auth.uid(),release_reason='Emergency admission financial override',notes=concat_ws(E'\n',notes,'Emergency admission financial override: treatment released before deposit.'),updated_at=now() WHERE id=v_order.id;
     INSERT INTO public.department_queues(service_order_id,patient_id,department,related_encounter_id,related_invoice_id,payment_required,payment_satisfied,priority,reason,created_by,queued_at,status)
     VALUES(v_order.id,v_order.patient_id,v_order.department,v_order.encounter_id,v_order.invoice_id,v_order.payment_required,TRUE,'normal',v_order.service_name,auth.uid(),now(),'queued')
     ON CONFLICT(service_order_id) DO UPDATE SET payment_satisfied=TRUE,status=CASE WHEN public.department_queues.status='cancelled' THEN 'queued' ELSE public.department_queues.status END,updated_at=now();
   END LOOP;
   PERFORM public.record_system_audit('admission_financial_override','admissions','admission',v_admission,'critical',jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'override',TRUE));
 END IF;
 PERFORM public.record_system_audit('patient_admitted','admissions','admission',v_admission,'info',jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'financial_override',v_override));
 RETURN jsonb_build_object('admission_id',v_admission,'override',v_override,'status','admitted');
END; $$;

CREATE OR REPLACE FUNCTION public.discharge_admission_workflow(_admission_id UUID,_summary TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); a public.admissions%ROWTYPE; p public.patients%ROWTYPE; n UUID;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Admission discharge is not permitted'; END IF;
 SELECT * INTO a FROM public.admissions WHERE id=_admission_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Admission not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=a.patient_id) THEN RAISE EXCEPTION 'Admission patient not found'; END IF;
 IF a.status='discharged' THEN
   SELECT id INTO n FROM public.notifications WHERE related_entity_id=a.id AND category='payment' AND recipient_role='accountant' AND metadata->>'workflow'='discharge_billing_handoff' ORDER BY created_at DESC LIMIT 1;
   RETURN jsonb_build_object('admission_id',a.id,'patient_id',a.patient_id,'status','discharged','billing_handoff','pending','existing',TRUE,'notification_id',n);
 END IF;
 IF a.status<>'admitted' THEN RAISE EXCEPTION 'Admission is not active'; END IF;
 UPDATE public.admissions SET status='discharged',discharged_at=now(),discharge_summary=COALESCE(NULLIF(btrim(_summary),''),'Discharged from inpatient admission.') WHERE id=a.id;
 SELECT * INTO p FROM public.patients WHERE id=a.patient_id;
 SELECT id INTO n FROM public.notifications WHERE related_entity_id=a.id AND category='payment' AND recipient_role='accountant' AND metadata->>'workflow'='discharge_billing_handoff' ORDER BY created_at DESC LIMIT 1;
 IF n IS NULL THEN
   INSERT INTO public.notifications(recipient_role,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
   VALUES('accountant','Discharged patient ready for billing reconciliation',format('%s (%s) has been discharged. Reconcile the complete patient bill, including inpatient services, before settlement.',COALESCE(p.first_name||' '||p.last_name,'Patient'),COALESCE(p.patient_code,'no patient code')),'warning','payment','/billing',a.patient_id,a.id,jsonb_build_object('workflow','discharge_billing_handoff','admission_id',a.id,'discharged_at',now()))
   RETURNING id INTO n;
 END IF;
 PERFORM public.record_system_audit('patient_discharged','admissions','admission',a.id,'info',jsonb_build_object('patient_id',a.patient_id,'billing_handoff_notification_id',n));
 RETURN jsonb_build_object('admission_id',a.id,'patient_id',a.patient_id,'status','discharged','billing_handoff','pending','notification_id',n);
END; $$;

REVOKE ALL ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) TO authenticated;
