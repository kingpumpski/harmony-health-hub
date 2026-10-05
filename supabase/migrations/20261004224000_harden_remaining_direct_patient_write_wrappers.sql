-- Pin remaining direct clinical/billing write wrappers to facility-scoped execution.
CREATE OR REPLACE FUNCTION public.create_walk_in_billable_service(_patient_id uuid,_service_code text,_quantity integer DEFAULT 1,_notes text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE t public.service_tariffs%ROWTYPE; o uuid; inv uuid; item uuid; pf uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Billing access required'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF _quantity IS NULL OR _quantity<1 THEN RAISE EXCEPTION 'Quantity must be at least one'; END IF;
 SELECT * INTO t FROM public.service_tariffs WHERE service_code=_service_code AND active=true AND facility_id=pf LIMIT 1;
 IF t.id IS NULL THEN RAISE EXCEPTION 'Active service tariff not found'; END IF;
 SELECT i.id INTO inv FROM public.invoices i WHERE i.patient_id=_patient_id AND i.facility_id=pf AND i.status NOT IN ('paid','cancelled') ORDER BY i.created_at DESC LIMIT 1;
 IF inv IS NULL THEN INSERT INTO public.invoices(patient_id,facility_id,total_amount,paid_amount,status,created_by) VALUES(_patient_id,pf,0,0,'pending',auth.uid()) RETURNING id INTO inv; END IF;
 INSERT INTO public.invoice_items(invoice_id,facility_id,description,quantity,unit_price,amount,category,department,source_type,source_id,paid_amount) VALUES(inv,pf,t.service_name,_quantity,t.amount,t.amount*_quantity,'procedure',t.department,'walk_in',gen_random_uuid(),0) RETURNING id INTO item;
 INSERT INTO public.service_orders(patient_id,facility_id,department,service_name,amount,status,notes,requested_by,order_type,service_code,quantity,unit_price,payment_required,created_by,invoice_id,invoice_item_id) VALUES(_patient_id,pf,t.department,t.service_name,t.amount*_quantity,'pending_payment_approval',_notes,auth.uid(),'walk_in',t.service_code,_quantity,t.amount,true,auth.uid(),inv,item) RETURNING id INTO o;
 UPDATE public.invoice_items SET service_order_id=o,source_id=o WHERE id=item; RETURN o;
END;$function$;
REVOKE ALL ON FUNCTION public.create_walk_in_billable_service(uuid,text,integer,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_walk_in_billable_service(uuid,text,integer,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_walk_in_billable_service(uuid,text,integer,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_triage_assessment_offline(_id uuid,_patient_id uuid,_systolic integer DEFAULT NULL,_diastolic integer DEFAULT NULL,_heart_rate integer DEFAULT NULL,_temperature numeric DEFAULT NULL,_respiratory_rate integer DEFAULT NULL,_oxygen_saturation numeric DEFAULT NULL,_weight_kg numeric DEFAULT NULL,_height_m numeric DEFAULT NULL,_pain_score integer DEFAULT NULL,_consciousness text DEFAULT NULL,_presenting_complaint text DEFAULT NULL,_clinical_notes text DEFAULT NULL,_priority text DEFAULT 'routine')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_existing uuid; v_inserted uuid; v_bmi numeric(7,2); v_priority text:=pg_catalog.lower(pg_catalog.trim(coalesce(_priority,'routine'))); pf uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to record triage'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF _id IS NULL THEN RAISE EXCEPTION 'Offline triage id is required'; END IF;
 IF v_priority NOT IN ('critical','urgent','moderate','routine') THEN RAISE EXCEPTION 'Invalid triage priority'; END IF;
 IF _pain_score IS NOT NULL AND (_pain_score<0 OR _pain_score>10) THEN RAISE EXCEPTION 'Pain score must be between 0 and 10'; END IF;
 IF _systolic IS NOT NULL AND (_systolic<0 OR _systolic>400) THEN RAISE EXCEPTION 'SBP must be between 0 and 400 mmHg'; END IF;
 IF _diastolic IS NOT NULL AND (_diastolic<0 OR _diastolic>300) THEN RAISE EXCEPTION 'DBP must be between 0 and 300 mmHg'; END IF;
 IF _heart_rate IS NOT NULL AND (_heart_rate<0 OR _heart_rate>300) THEN RAISE EXCEPTION 'Heart rate must be between 0 and 300 bpm'; END IF;
 IF _temperature IS NOT NULL AND (_temperature<20 OR _temperature>50) THEN RAISE EXCEPTION 'Temperature must be between 20 and 50 °C'; END IF;
 IF _respiratory_rate IS NOT NULL AND (_respiratory_rate<0 OR _respiratory_rate>100) THEN RAISE EXCEPTION 'Respiratory rate must be between 0 and 100 per minute'; END IF;
 IF _oxygen_saturation IS NOT NULL AND (_oxygen_saturation<0 OR _oxygen_saturation>100) THEN RAISE EXCEPTION 'Oxygen saturation must be between 0 and 100 percent'; END IF;
 IF _weight_kg IS NOT NULL AND (_weight_kg<=0 OR _weight_kg>500) THEN RAISE EXCEPTION 'Weight must be greater than 0 and no more than 500 kg'; END IF;
 IF _height_m IS NOT NULL AND (_height_m<=0 OR _height_m>3) THEN RAISE EXCEPTION 'Height must be entered in metres and be between 0 and 3 m'; END IF;
 IF _weight_kg IS NULL AND _height_m IS NULL AND _systolic IS NULL AND _diastolic IS NULL AND _heart_rate IS NULL AND _temperature IS NULL AND _respiratory_rate IS NULL AND _oxygen_saturation IS NULL THEN RAISE EXCEPTION 'At least one measured vital sign is required'; END IF;
 IF _weight_kg IS NOT NULL AND _height_m IS NOT NULL THEN v_bmi:=round((_weight_kg/pg_catalog.power(_height_m,2))::numeric,2); END IF;
 INSERT INTO public.triage_assessments(id,facility_id,patient_id,recorded_by,systolic,diastolic,heart_rate,temperature,respiratory_rate,oxygen_saturation,weight_kg,height_m,bmi,pain_score,consciousness,presenting_complaint,clinical_notes,priority,is_critical) VALUES(_id,pf,_patient_id,auth.uid(),_systolic,_diastolic,_heart_rate,_temperature,_respiratory_rate,_oxygen_saturation,_weight_kg,_height_m,v_bmi,_pain_score,NULLIF(pg_catalog.trim(_consciousness),''),NULLIF(pg_catalog.trim(_presenting_complaint),''),NULLIF(pg_catalog.trim(_clinical_notes),''),v_priority,v_priority='critical') ON CONFLICT(id) DO NOTHING RETURNING id INTO v_inserted;
 IF v_inserted IS NULL THEN SELECT id INTO v_existing FROM public.triage_assessments WHERE id=_id AND facility_id=pf; RETURN jsonb_build_object('triage_id',v_existing,'already_recorded',true); END IF;
 RETURN jsonb_build_object('triage_id',v_inserted,'already_recorded',false);
END;$function$;
REVOKE ALL ON FUNCTION public.record_triage_assessment_offline(uuid,uuid,integer,integer,integer,numeric,integer,numeric,numeric,numeric,integer,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_triage_assessment_offline(uuid,uuid,integer,integer,integer,numeric,integer,numeric,numeric,numeric,integer,text,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_triage_assessment_offline(uuid,uuid,integer,integer,integer,numeric,integer,numeric,numeric,numeric,integer,text,text,text,text) TO authenticated;

ALTER FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) SET search_path = '';
REVOKE ALL ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) TO authenticated;
