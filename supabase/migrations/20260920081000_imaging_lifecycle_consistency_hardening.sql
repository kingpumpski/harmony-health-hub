-- Harden imaging lifecycle identity, payment and notification replay boundaries.
CREATE OR REPLACE FUNCTION public.create_imaging_order_with_payment_gate(
  _patient_id UUID,_encounter_id UUID DEFAULT NULL,_modality TEXT DEFAULT 'X-Ray',
  _study_name TEXT DEFAULT 'General study',_body_site TEXT DEFAULT NULL,
  _priority TEXT DEFAULT 'routine',_clinical_indication TEXT DEFAULT NULL,_amount NUMERIC DEFAULT 0
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); eid UUID; iid UUID; sid UUID; st TEXT; es TEXT;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'radiologist') OR public.has_role(uid,'radiology_technician') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Imaging order access required'; END IF;
 IF _patient_id IS NULL OR NULLIF(btrim(_study_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and study name are required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 IF _encounter_id IS NOT NULL THEN
   SELECT patient_id,status INTO eid,es FROM public.encounters WHERE id=_encounter_id;
   IF NOT FOUND OR eid<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to patient'; END IF;
   IF es IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot create imaging for a closed encounter'; END IF;
 END IF;
 IF COALESCE(_amount,0)<0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF;
 INSERT INTO public.imaging_orders(patient_id,encounter_id,modality,study_name,body_site,priority,clinical_indication,amount,status,requested_by)
 VALUES(_patient_id,_encounter_id,btrim(COALESCE(_modality,'X-Ray')),btrim(_study_name),NULLIF(btrim(_body_site),''),COALESCE(NULLIF(btrim(_priority),''),'routine'),NULLIF(btrim(_clinical_indication),''),COALESCE(_amount,0),CASE WHEN COALESCE(_amount,0)>0 THEN 'pending_payment_approval' ELSE 'released' END,uid)
 RETURNING id,status INTO iid,st;
 IF COALESCE(_amount,0)>0 THEN
   INSERT INTO public.service_orders(patient_id,encounter_id,department,service_name,amount,status,requested_by,related_entity_id,order_type,service_code,payment_required,created_by,notes)
   VALUES(_patient_id,_encounter_id,'imaging',btrim(_study_name),COALESCE(_amount,0),'pending_payment_approval',uid,iid,'imaging',upper(btrim(COALESCE(_modality,'X-RAY'))),true,uid,NULLIF(btrim(_clinical_indication),''))
   RETURNING id INTO sid;
   UPDATE public.imaging_orders SET service_order_id=sid WHERE id=iid;
 END IF;
 RETURN jsonb_build_object('imaging_order_id',iid,'service_order_id',sid,'status',st);
END; $$;

CREATE OR REPLACE FUNCTION public.start_imaging_order(_imaging_order_id UUID)
RETURNS public.imaging_orders LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); o public.imaging_orders; s public.service_orders; es TEXT;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'radiologist') OR public.has_role(uid,'radiology_technician') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Radiology role required'; END IF;
 SELECT * INTO o FROM public.imaging_orders WHERE id=_imaging_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
 IF o.status<>'released' THEN RAISE EXCEPTION 'Imaging order must be released before it can start'; END IF;
 IF o.encounter_id IS NOT NULL THEN SELECT status INTO es FROM public.encounters WHERE id=o.encounter_id; IF es IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot start imaging for a closed encounter'; END IF; END IF;
 IF o.service_order_id IS NULL THEN
   UPDATE public.imaging_orders SET status='in_progress',performed_by=uid,updated_at=now() WHERE id=o.id RETURNING * INTO o; RETURN o;
 END IF;
 SELECT * INTO s FROM public.service_orders WHERE id=o.service_order_id FOR UPDATE;
 IF NOT FOUND OR s.patient_id<>o.patient_id OR s.related_entity_id<>o.id OR s.department<>'imaging' THEN RAISE EXCEPTION 'Imaging service order linkage is invalid'; END IF;
 IF s.status<>'released' THEN RAISE EXCEPTION 'Linked service order must be released before imaging can start'; END IF;
 UPDATE public.service_orders SET status='in_progress',started_at=COALESCE(started_at,now()),updated_at=now() WHERE id=s.id;
 UPDATE public.department_queues SET status='claimed',claimed_by=uid,assigned_to=uid,claimed_at=COALESCE(claimed_at,now()),updated_at=now() WHERE service_order_id=s.id;
 UPDATE public.imaging_orders SET status='in_progress',performed_by=uid,updated_at=now() WHERE id=o.id RETURNING * INTO o;
 RETURN o;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_imaging_order(_imaging_order_id UUID,_report TEXT,_impression TEXT)
RETURNS public.imaging_orders LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); o public.imaging_orders; s public.service_orders; es TEXT;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'radiologist') OR public.has_role(uid,'radiology_technician') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Radiology role required'; END IF;
 IF NULLIF(btrim(COALESCE(_report,'')),'') IS NULL AND NULLIF(btrim(COALESCE(_impression,'')),'') IS NULL THEN RAISE EXCEPTION 'A report or impression is required before completion'; END IF;
 SELECT * INTO o FROM public.imaging_orders WHERE id=_imaging_order_id FOR UPDATE;
 IF NOT FOUND OR o.status<>'in_progress' THEN RAISE EXCEPTION 'Imaging order must be in progress before completion'; END IF;
 IF o.encounter_id IS NOT NULL THEN SELECT status INTO es FROM public.encounters WHERE id=o.encounter_id; IF es IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot complete imaging for a closed encounter'; END IF; END IF;
 IF o.service_order_id IS NOT NULL THEN
   SELECT * INTO s FROM public.service_orders WHERE id=o.service_order_id FOR UPDATE;
   IF NOT FOUND OR s.patient_id<>o.patient_id OR s.related_entity_id<>o.id OR s.department<>'imaging' THEN RAISE EXCEPTION 'Imaging service order linkage is invalid'; END IF;
   IF s.status<>'in_progress' THEN RAISE EXCEPTION 'Linked service order must be in progress before imaging completion'; END IF;
   UPDATE public.service_orders SET status='completed',completed_at=now(),updated_at=now() WHERE id=s.id;
   UPDATE public.department_queues SET status='completed',completed_at=now(),updated_at=now() WHERE service_order_id=s.id;
 END IF;
 UPDATE public.imaging_orders SET report=NULLIF(btrim(COALESCE(_report,'')),''),impression=NULLIF(btrim(COALESCE(_impression,'')),''),status='completed',updated_at=now() WHERE id=o.id RETURNING * INTO o;
 IF o.requested_by IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.notifications WHERE recipient_user_id=o.requested_by AND related_entity_id=o.id AND category='other' AND title='Radiology report ready') THEN
   INSERT INTO public.notifications(recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
   VALUES(o.requested_by,'Radiology report ready',format('The %s report for this patient is complete and ready for clinical review.',o.study_name),CASE WHEN lower(COALESCE(o.priority,'routine')) IN('urgent','stat') THEN 'warning' ELSE 'info' END,'other','/radiology',o.patient_id,o.id,jsonb_build_object('workflow','imaging_result_review','imaging_order_id',o.id,'encounter_id',o.encounter_id,'service_order_id',o.service_order_id,'priority',o.priority));
 END IF;
 RETURN o;
END; $$;

REVOKE ALL ON FUNCTION public.create_imaging_order_with_payment_gate(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.start_imaging_order(UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.complete_imaging_order(UUID,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_imaging_order_with_payment_gate(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_imaging_order(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_imaging_order(UUID,TEXT,TEXT) TO authenticated;
