-- Harden pharmacy dispensing, care-transition and patient-document facility boundaries.
BEGIN;

-- The live RPC bodies are deliberately replaced here, not merely ALTERed, so this migration
-- reproduces the authorization and facility-lineage controls in a fresh environment.

CREATE OR REPLACE FUNCTION public.prepare_pharmacy_dispensing(_prescription_id uuid,_inventory_id uuid,_quantity integer,_notes text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE p public.prescriptions;i public.pharmacy_inventory;existing public.pharmacy_dispensing_plans;plan_id uuid;order_id uuid;price numeric;encounter_status text;uid uuid:=auth.uid();pf uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
 IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 SELECT * INTO p FROM public.prescriptions WHERE id=_prescription_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Prescription not found'; END IF;
 pf:=public.assert_patient_facility_context(p.patient_id);
 IF p.facility_id IS NULL OR p.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'Prescription facility attribution is unresolved or mismatched'; END IF;
 SELECT * INTO i FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE; IF NOT FOUND OR NOT i.active THEN RAISE EXCEPTION 'Inventory item not found or inactive'; END IF;
 IF _quantity>COALESCE(p.computed_quantity,_quantity) THEN RAISE EXCEPTION 'Dispensing quantity exceeds prescribed quantity'; END IF;
 IF i.stock_quantity<_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
 IF p.encounter_id IS NOT NULL THEN SELECT status INTO encounter_status FROM public.encounters WHERE id=p.encounter_id; IF NOT FOUND OR encounter_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Prescription is linked to a closed or missing encounter'; END IF; END IF;
 SELECT * INTO existing FROM public.pharmacy_dispensing_plans WHERE prescription_id=p.id AND status='unpaid' ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 IF FOUND THEN RETURN jsonb_build_object('plan_id',existing.id,'service_order_id',existing.service_order_id,'amount',(SELECT amount FROM public.service_orders WHERE id=existing.service_order_id),'status','unpaid','existing',true); END IF;
 price:=COALESCE(i.unit_price,0);
 INSERT INTO public.pharmacy_dispensing_plans(prescription_id,patient_id,inventory_id,medication_name,prescribed_dose,prescribed_frequency,prescribed_duration,computed_quantity,prepared_quantity,prepared_by,notes,facility_id)
 VALUES(p.id,p.patient_id,i.id,i.drug_name,p.dosage,p.frequency,p.duration,p.computed_quantity,_quantity,uid,_notes,pf) RETURNING id INTO plan_id;
 INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes,facility_id)
 VALUES(p.patient_id,'pharmacy','Dispense: '||i.drug_name,price*_quantity,p.id,'pending_payment_approval',uid,'drug',i.id,'Pharmacy preparation '||plan_id::text,pf) RETURNING id INTO order_id;
 UPDATE public.pharmacy_dispensing_plans SET service_order_id=order_id,updated_at=pg_catalog.now() WHERE id=plan_id;
 RETURN jsonb_build_object('plan_id',plan_id,'service_order_id',order_id,'amount',price*_quantity,'status','unpaid');
END; $$;

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_dispense(_plan_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE p public.pharmacy_dispensing_plans;i public.pharmacy_inventory;r public.prescriptions;so public.service_orders;uid uuid:=auth.uid();pf uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
 SELECT * INTO p FROM public.pharmacy_dispensing_plans WHERE id=_plan_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Dispensing plan not found'; END IF;
 pf:=public.assert_patient_facility_context(p.patient_id);
 IF p.facility_id IS NULL OR p.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'Dispensing plan facility attribution is unresolved or mismatched'; END IF;
 SELECT * INTO r FROM public.prescriptions WHERE id=p.prescription_id FOR UPDATE; IF NOT FOUND OR r.patient_id<>p.patient_id OR r.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'Prescription facility linkage is invalid'; END IF;
 SELECT * INTO so FROM public.service_orders WHERE id=p.service_order_id FOR UPDATE; IF NOT FOUND OR so.patient_id<>p.patient_id OR so.related_entity_id<>p.prescription_id OR so.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'Dispensing service order facility linkage is invalid'; END IF;
 SELECT * INTO i FROM public.pharmacy_inventory WHERE id=p.inventory_id FOR UPDATE; IF NOT FOUND OR NOT i.active OR i.stock_quantity<p.prepared_quantity THEN RAISE EXCEPTION 'Insufficient or unavailable stock'; END IF;
 IF p.status<>'unpaid' THEN RAISE EXCEPTION 'Dispensing plan is already processed'; END IF;
 IF so.status NOT IN('released','in_progress') THEN RAISE EXCEPTION 'Payment has not been received or the pharmacy order has not been released'; END IF;
 UPDATE public.pharmacy_inventory SET stock_quantity=stock_quantity-p.prepared_quantity,updated_at=pg_catalog.now() WHERE id=i.id;
 UPDATE public.pharmacy_dispensing_plans SET status='dispensed',dispensed_by=uid,dispensed_at=pg_catalog.now(),updated_at=pg_catalog.now() WHERE id=p.id;
 UPDATE public.prescriptions SET status='dispensed',dispensed_by=uid,dispensed_at=pg_catalog.now(),updated_at=pg_catalog.now() WHERE id=r.id AND status IN('pending','paid');
 UPDATE public.service_orders SET status='completed',completed_at=COALESCE(completed_at,pg_catalog.now()),updated_at=pg_catalog.now() WHERE id=so.id AND status IN('released','in_progress');
 RETURN jsonb_build_object('plan_id',p.id,'status','dispensed','dispensed_by',uid);
END; $$;

CREATE OR REPLACE FUNCTION public.create_care_transition_workflow(_patient_id uuid,_transition_type text,_destination text DEFAULT NULL::text,_summary text DEFAULT NULL::text,_medications_reconciled boolean DEFAULT false,_follow_up_required boolean DEFAULT false,_follow_up_date date DEFAULT NULL::date,_instructions text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid;pf uuid;uid uuid:=auth.uid();
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
END; $$;

CREATE OR REPLACE FUNCTION public.upload_patient_document_metadata(_patient_id uuid,_document_type text,_file_name text,_storage_path text,_mime_type text DEFAULT NULL::text,_file_size bigint DEFAULT NULL::bigint,_notes text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE uid uuid:=auth.uid();v_id uuid;pf uuid;v_type text:=NULLIF(pg_catalog.btrim(COALESCE(_document_type,'')),'');v_name text:=NULLIF(pg_catalog.btrim(COALESCE(_file_name,'')),'');v_path text:=NULLIF(pg_catalog.btrim(COALESCE(_storage_path,'')),'');v_prefix text;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Document creation is not permitted'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF v_type IS NULL OR v_name IS NULL OR v_path IS NULL THEN RAISE EXCEPTION 'Document type, file name and storage path are required'; END IF;
 v_prefix:=_patient_id::text || '/';
 IF pg_catalog.left(v_path,pg_catalog.length(v_prefix))<>v_prefix THEN RAISE EXCEPTION 'Storage path must be scoped to the patient'; END IF;
 IF _file_size IS NULL OR _file_size<=0 OR _file_size>10485760 THEN RAISE EXCEPTION 'Invalid document size'; END IF;
 INSERT INTO public.patient_documents(patient_id,document_type,file_name,storage_path,mime_type,file_size,notes,uploaded_by,facility_id)
 VALUES(_patient_id,v_type,v_name,v_path,NULLIF(pg_catalog.btrim(COALESCE(_mime_type,'')),''),_file_size,NULLIF(pg_catalog.btrim(COALESCE(_notes,'')),''),uid,pf) RETURNING id INTO v_id;
 RETURN jsonb_build_object('document_id',v_id,'patient_id',_patient_id,'storage_path',v_path);
END; $$;

REVOKE ALL ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) TO authenticated;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_dispense(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_dispense(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_care_transition_workflow(uuid,text,text,text,boolean,boolean,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_care_transition_workflow(uuid,text,text,text,boolean,boolean,date,text) TO authenticated;
REVOKE ALL ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) TO authenticated;

COMMIT;
