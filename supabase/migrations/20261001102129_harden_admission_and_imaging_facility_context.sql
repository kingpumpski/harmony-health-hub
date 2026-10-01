BEGIN;

CREATE OR REPLACE FUNCTION public.create_admission_workflow(_patient_id uuid,_ward text,_bed text DEFAULT NULL::text,_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); v_patient_facility uuid; v_admission uuid; v_bed_id uuid; v_ward_name text; v_bed_ward uuid; v_ward_facility uuid; v_transfer jsonb; v_ward_input text:=NULLIF(pg_catalog.btrim(_ward),''); v_bed_input text:=NULLIF(pg_catalog.btrim(_bed),'');
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Admission creation is not permitted'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=_patient_id AND coalesce(status,'active')<>'inactive' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_facility IS NULL OR v_facility IS DISTINCT FROM v_patient_facility) THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 IF v_ward_input IS NULL THEN RAISE EXCEPTION 'Ward is required'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(_patient_id::text,0));
 IF EXISTS(SELECT 1 FROM public.admissions WHERE patient_id=_patient_id AND status='admitted') THEN RAISE EXCEPTION 'Patient already has an active admission'; END IF;
 SELECT wu.id,wu.name,wu.facility_id INTO v_bed_ward,v_ward_name,v_ward_facility FROM public.ward_units wu WHERE wu.active=true AND (lower(pg_catalog.btrim(wu.name))=lower(v_ward_input) OR lower(pg_catalog.btrim(wu.code))=lower(v_ward_input)) AND wu.facility_id=v_patient_facility ORDER BY wu.name LIMIT 1;
 IF v_bed_ward IS NULL THEN RAISE EXCEPTION 'Active ward not found in the patient facility'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND NOT public.has_facility_access(uid,v_ward_facility) THEN RAISE EXCEPTION 'Facility access required for admission ward'; END IF;
 IF v_bed_input IS NOT NULL THEN
   IF v_bed_input !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN RAISE EXCEPTION 'Bed must be a valid ward bed ID'; END IF;
   v_bed_id:=v_bed_input::uuid;
   SELECT wb.ward_id INTO v_bed_ward FROM public.ward_beds wb WHERE wb.id=v_bed_id FOR SHARE;
   IF v_bed_ward IS NULL THEN RAISE EXCEPTION 'Bed not found'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.ward_units wu WHERE wu.id=v_bed_ward AND wu.active=true AND wu.facility_id=v_patient_facility AND (lower(pg_catalog.btrim(wu.name))=lower(v_ward_input) OR lower(pg_catalog.btrim(wu.code))=lower(v_ward_input))) THEN RAISE EXCEPTION 'Bed does not belong to the selected ward and patient facility'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.ward_beds wb WHERE wb.id=v_bed_id AND wb.facility_id=v_patient_facility) THEN RAISE EXCEPTION 'Bed does not belong to the admission facility'; END IF;
 END IF;
 INSERT INTO public.admissions(patient_id,ward,bed,reason,admitted_by,status,admitted_at,facility_id) VALUES(_patient_id,v_ward_name,NULLIF(v_bed_input,''),NULLIF(pg_catalog.btrim(_reason),''),uid,'admitted',now(),v_patient_facility) RETURNING id INTO v_admission;
 IF v_bed_id IS NOT NULL THEN
   v_transfer:=public.transfer_patient_ward_bed_workflow(_patient_id,v_admission,v_bed_id,NULL,NULL,NULL);
   RETURN pg_catalog.jsonb_build_object('admission_id',v_admission,'status','admitted','bed_placement',v_transfer);
 END IF;
 RETURN pg_catalog.jsonb_build_object('admission_id',v_admission,'status','admitted','bed_placement',NULL,'awaiting_bed',TRUE);
END; $function$;

CREATE OR REPLACE FUNCTION public.create_imaging_order_with_payment_gate(_patient_id uuid,_encounter_id uuid DEFAULT NULL::uuid,_modality text DEFAULT 'X-Ray',_study_name text DEFAULT 'General study',_body_site text DEFAULT NULL::text,_priority text DEFAULT 'routine',_clinical_indication text DEFAULT NULL::text,_amount numeric DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE uid uuid:=auth.uid(); v_active_facility uuid:=public.current_user_facility_id(); v_patient_facility uuid; v_encounter_facility uuid; eid uuid; iid uuid; sid uuid; st text; es text;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'radiologist') OR public.has_role(uid,'radiology_technician') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Imaging order access required'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=_patient_id AND coalesce(status,'active')<>'inactive' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active patient does not exist'; END IF;
 IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_active_facility IS NULL OR v_patient_facility IS DISTINCT FROM v_active_facility) THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 IF _encounter_id IS NOT NULL THEN
   SELECT patient_id,status,facility_id INTO eid,es,v_encounter_facility FROM public.encounters WHERE id=_encounter_id FOR SHARE;
   IF NOT FOUND OR eid<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to patient'; END IF;
   IF es IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot create imaging for a closed encounter'; END IF;
   IF v_encounter_facility IS NULL OR v_encounter_facility IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 END IF;
 IF coalesce(_amount,0)<0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF;
 INSERT INTO public.imaging_orders(patient_id,encounter_id,modality,study_name,body_site,priority,clinical_indication,amount,status,requested_by,facility_id)
 VALUES(_patient_id,_encounter_id,btrim(coalesce(_modality,'X-Ray')),btrim(_study_name),NULLIF(btrim(_body_site),''),coalesce(NULLIF(btrim(_priority),''),'routine'),NULLIF(btrim(_clinical_indication),''),coalesce(_amount,0),case when coalesce(_amount,0)>0 then 'pending_payment_approval' else 'released' end,uid,v_patient_facility)
 RETURNING id,status INTO iid,st;
 IF coalesce(_amount,0)>0 THEN
   INSERT INTO public.service_orders(patient_id,encounter_id,department,service_name,amount,status,requested_by,related_entity_id,order_type,service_code,payment_required,created_by,notes,facility_id)
   VALUES(_patient_id,_encounter_id,'imaging',btrim(_study_name),coalesce(_amount,0),'pending_payment_approval',uid,iid,'imaging',upper(btrim(coalesce(_modality,'X-RAY'))),true,uid,NULLIF(btrim(_clinical_indication),''),v_patient_facility)
   RETURNING id INTO sid;
   UPDATE public.imaging_orders SET service_order_id=sid WHERE id=iid;
 END IF;
 RETURN jsonb_build_object('imaging_order_id',iid,'service_order_id',sid,'status',st);
END; $function$;

REVOKE ALL ON FUNCTION public.create_admission_workflow(uuid,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(uuid,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) TO authenticated;
COMMIT;