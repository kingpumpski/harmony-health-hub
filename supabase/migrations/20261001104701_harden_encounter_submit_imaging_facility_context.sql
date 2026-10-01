-- Harden encounter submission and imaging lifecycle facility boundaries.
BEGIN;

CREATE OR REPLACE FUNCTION public.submit_encounter_workflow(
  _encounter_id uuid,
  _specialty text DEFAULT NULL::text,
  _appointment_date timestamptz DEFAULT NULL::timestamptz,
  _referral_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_enc public.encounters%rowtype;
  v_referral uuid;
  v_snapshot jsonb;
  v_version integer;
  v_require_principal boolean := true;
  v_patient_facility uuid;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF v_enc.id IS NULL THEN RAISE EXCEPTION 'Encounter not found'; END IF;
  v_patient_facility := public.assert_patient_facility_context(v_enc.patient_id);
  IF v_enc.facility_id IS NULL THEN RAISE EXCEPTION 'Encounter facility attribution is unresolved'; END IF;
  IF v_enc.facility_id IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION 'Encounter or patient belongs to a different facility context';
  END IF;
  IF v_enc.practitioner_id<>v_uid
     AND NOT public.has_role(v_uid,'admin')
     AND NOT public.has_role(v_uid,'it_admin') THEN
    RAISE EXCEPTION 'Only the encounter creator can submit this document';
  END IF;
  IF v_enc.status='completed' THEN RAISE EXCEPTION 'Encounter is already submitted'; END IF;
  SELECT coalesce(require_principal_diagnosis_for_final,true) INTO v_require_principal
  FROM public.facility_configuration ORDER BY created_at asc LIMIT 1;
  IF v_require_principal AND NOT EXISTS(
    SELECT 1 FROM public.diagnoses d WHERE d.encounter_id=v_enc.id AND d.is_principal=true
  ) THEN RAISE EXCEPTION 'Principal diagnosis required before final submission'; END IF;
  IF nullif(pg_catalog.btrim(v_enc.treatment_plan),'') IS NULL
     AND EXISTS(select 1 from public.prescriptions p where p.encounter_id=v_enc.id) THEN
    RAISE EXCEPTION 'Treatment plan is required when prescriptions are documented';
  END IF;
  IF nullif(pg_catalog.btrim(_specialty),'') IS NOT NULL THEN
    IF _appointment_date IS NULL THEN RAISE EXCEPTION 'Referral appointment date is required'; END IF;
    INSERT INTO public.patient_referrals(
      patient_id,encounter_id,referred_by,destination,specialty,reason,urgency,status,
      clinical_summary,appointment_date,facility_id
    )
    VALUES(
      v_enc.patient_id,v_enc.id,v_uid,'Specialist Clinic',pg_catalog.btrim(_specialty),
      coalesce(nullif(pg_catalog.btrim(_referral_reason),''),'Specialist review requested'),
      'routine','requested',coalesce(v_enc.treatment_plan,v_enc.principal_diagnosis),
      _appointment_date,v_patient_facility
    )
    RETURNING id INTO v_referral;
  END IF;
  v_version:=greatest(coalesce(v_enc.version_no,1),1);
  v_snapshot:=jsonb_build_object(
    'encounter',to_jsonb(v_enc),
    'diagnoses',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at,d.id) from public.diagnoses d where d.encounter_id=v_enc.id),'[]'::jsonb),
    'prescriptions',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at,p.id) from public.prescriptions p where p.encounter_id=v_enc.id),'[]'::jsonb),
    'referral_id',v_referral,
    'workflow_requirements',jsonb_build_object('require_principal_diagnosis',v_require_principal)
  );
  UPDATE public.encounters
  SET status='completed',submitted_at=pg_catalog.now(),submitted_by=v_uid,locked_at=pg_catalog.now(),
      version_no=v_version,updated_at=pg_catalog.now()
  WHERE id=_encounter_id;
  INSERT INTO public.document_versions(entity_type,entity_id,version_no,action,snapshot,changed_by)
  VALUES('encounter',v_enc.id,v_version,'submitted',v_snapshot,v_uid)
  ON CONFLICT(entity_type,entity_id,version_no,action) DO NOTHING;
  PERFORM public.record_system_audit(
    'encounter_submitted','clinical','encounter',v_enc.id,'info',
    jsonb_build_object('patient_id',v_enc.patient_id,'version_no',v_version,'referral_id',v_referral,
      'require_principal_diagnosis',v_require_principal)
  );
  RETURN jsonb_build_object('encounter_id',v_enc.id,'status','completed','version_no',v_version,
    'referral_id',v_referral,'require_principal_diagnosis',v_require_principal);
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_imaging_order(_imaging_order_id uuid)
RETURNS public.imaging_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE uid uuid:=auth.uid(); o public.imaging_orders; s public.service_orders; es text; v_patient_facility uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'radiologist') OR public.has_role(uid,'radiology_technician') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Radiology role required'; END IF;
 SELECT * INTO o FROM public.imaging_orders WHERE id=_imaging_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
 v_patient_facility := public.assert_patient_facility_context(o.patient_id);
 IF o.facility_id IS NULL THEN RAISE EXCEPTION 'Imaging order facility attribution is unresolved'; END IF;
 IF o.facility_id IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION 'Imaging order belongs to a different facility context'; END IF;
 IF o.status<>'released' THEN RAISE EXCEPTION 'Imaging order must be released before it can start'; END IF;
 IF o.encounter_id IS NOT NULL THEN SELECT status INTO es FROM public.encounters WHERE id=o.encounter_id; IF es IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot start imaging for a closed encounter'; END IF; END IF;
 IF o.service_order_id IS NULL THEN
   UPDATE public.imaging_orders SET status='in_progress',performed_by=uid,updated_at=pg_catalog.now() WHERE id=o.id RETURNING * INTO o; RETURN o;
 END IF;
 SELECT * INTO s FROM public.service_orders WHERE id=o.service_order_id FOR UPDATE;
 IF NOT FOUND OR s.patient_id<>o.patient_id OR s.related_entity_id<>o.id OR s.department<>'imaging' OR s.facility_id IS DISTINCT FROM v_patient_facility THEN
   RAISE EXCEPTION 'Imaging service order linkage or facility context is invalid';
 END IF;
 IF s.status<>'released' THEN RAISE EXCEPTION 'Linked service order must be released before imaging can start'; END IF;
 UPDATE public.service_orders SET status='in_progress',started_at=COALESCE(started_at,pg_catalog.now()),updated_at=pg_catalog.now() WHERE id=s.id;
 UPDATE public.department_queues SET status='claimed',claimed_by=uid,assigned_to=uid,claimed_at=COALESCE(claimed_at,pg_catalog.now()),updated_at=pg_catalog.now() WHERE service_order_id=s.id;
 UPDATE public.imaging_orders SET status='in_progress',performed_by=uid,updated_at=pg_catalog.now() WHERE id=o.id RETURNING * INTO o;
 RETURN o;
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_imaging_order(_imaging_order_id uuid,_report text,_impression text)
RETURNS public.imaging_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE uid uuid:=auth.uid(); o public.imaging_orders; s public.service_orders; es text; v_patient_facility uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'radiologist') OR public.has_role(uid,'radiology_technician') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Radiology role required'; END IF;
 IF NULLIF(pg_catalog.btrim(COALESCE(_report,'')),'') IS NULL AND NULLIF(pg_catalog.btrim(COALESCE(_impression,'')),'') IS NULL THEN RAISE EXCEPTION 'A report or impression is required before completion'; END IF;
 SELECT * INTO o FROM public.imaging_orders WHERE id=_imaging_order_id FOR UPDATE;
 IF NOT FOUND OR o.status<>'in_progress' THEN RAISE EXCEPTION 'Imaging order must be in progress before completion'; END IF;
 v_patient_facility := public.assert_patient_facility_context(o.patient_id);
 IF o.facility_id IS NULL THEN RAISE EXCEPTION 'Imaging order facility attribution is unresolved'; END IF;
 IF o.facility_id IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION 'Imaging order belongs to a different facility context'; END IF;
 IF o.encounter_id IS NOT NULL THEN SELECT status INTO es FROM public.encounters WHERE id=o.encounter_id; IF es IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot complete imaging for a closed encounter'; END IF; END IF;
 IF o.service_order_id IS NOT NULL THEN
   SELECT * INTO s FROM public.service_orders WHERE id=o.service_order_id FOR UPDATE;
   IF NOT FOUND OR s.patient_id<>o.patient_id OR s.related_entity_id<>o.id OR s.department<>'imaging' OR s.facility_id IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION 'Imaging service order linkage or facility context is invalid'; END IF;
   IF s.status<>'in_progress' THEN RAISE EXCEPTION 'Linked service order must be in progress before imaging completion'; END IF;
   UPDATE public.service_orders SET status='completed',completed_at=pg_catalog.now(),updated_at=pg_catalog.now() WHERE id=s.id;
   UPDATE public.department_queues SET status='completed',completed_at=pg_catalog.now(),updated_at=pg_catalog.now() WHERE service_order_id=s.id;
 END IF;
 UPDATE public.imaging_orders SET report=NULLIF(pg_catalog.btrim(COALESCE(_report,'')),''),impression=NULLIF(pg_catalog.btrim(COALESCE(_impression,'')),''),status='completed',updated_at=pg_catalog.now() WHERE id=o.id RETURNING * INTO o;
 IF o.requested_by IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.notifications WHERE recipient_user_id=o.requested_by AND related_entity_id=o.id AND category='other' AND title='Radiology report ready') THEN
   INSERT INTO public.notifications(recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
   VALUES(o.requested_by,'Radiology report ready',format('The %s report for this patient is complete and ready for clinical review.',o.study_name),CASE WHEN lower(COALESCE(o.priority,'routine')) IN('urgent','stat') THEN 'warning' ELSE 'info' END,'other','/radiology',o.patient_id,o.id,jsonb_build_object('workflow','imaging_result_review','imaging_order_id',o.id,'encounter_id',o.encounter_id,'service_order_id',o.service_order_id,'priority',o.priority));
 END IF;
 RETURN o;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_encounter_workflow(uuid,text,timestamptz,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_encounter_workflow(uuid,text,timestamptz,text) TO authenticated;
REVOKE ALL ON FUNCTION public.start_imaging_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_imaging_order(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.complete_imaging_order(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_imaging_order(uuid,text,text) TO authenticated;

COMMIT;
