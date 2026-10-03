-- Reproducible definitions for facility-context hardening applied live on 2026-10-03.
-- Safe to re-run: CREATE OR REPLACE and explicit privilege grants are idempotent.
CREATE OR REPLACE FUNCTION public.update_patient_workflow(_patient_id uuid, _changes jsonb)
RETURNS public.patients
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
declare
  uid uuid := auth.uid(); v_patient public.patients; v_role text;
  v_allowed_keys text[] := array['patient_code','first_name','last_name','date_of_birth','gender','email','phone','address','city','ghana_card_number','insurance_provider','insurance_number','insurance_group_number','insurance_expiry','emergency_contact_name','emergency_contact_phone','emergency_contact_relation','blood_group','genotype','allergies','chronic_conditions','status'];
  v_key text;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  select ur.role::text into v_role from public.user_roles ur where ur.user_id=uid order by ur.created_at desc limit 1;
  if v_role is null then raise exception 'Staff profile required'; end if;
  if v_role not in ('admin','front_desk','nurse','practitioner','midwife') then raise exception 'Patient update is not permitted'; end if;
  if _patient_id is null or _changes is null or jsonb_typeof(_changes) <> 'object' then raise exception 'Patient and changes are required'; end if;
  for v_key in select jsonb_object_keys(_changes) loop
    if not (v_key = any(v_allowed_keys)) then raise exception 'Patient field is not permitted: %', v_key; end if;
  end loop;
  if v_role='front_desk' and (_changes ? 'blood_group' or _changes ? 'genotype' or _changes ? 'allergies' or _changes ? 'chronic_conditions') then raise exception 'Clinical patient fields require a clinical role'; end if;
  if v_role in ('nurse','practitioner','midwife') and (_changes ? 'patient_code' or _changes ? 'ghana_card_number' or _changes ? 'insurance_provider' or _changes ? 'insurance_number' or _changes ? 'insurance_group_number' or _changes ? 'insurance_expiry' or _changes ? 'status') then raise exception 'Administrative patient fields require an administrative role'; end if;
  if _changes ? 'status' and coalesce(_changes->>'status','') not in ('active','inactive','discharged') then raise exception 'Invalid patient status'; end if;
  select * into v_patient from public.patients where id=_patient_id for update;
  if not found then raise exception 'Patient not found'; end if;
  perform public.assert_patient_facility_context(v_patient.id);
  if v_patient.facility_id is null then raise exception 'Patient facility attribution is unresolved'; end if;
  update public.patients set
    patient_code=case when _changes ? 'patient_code' then nullif(pg_catalog.btrim(_changes->>'patient_code'),'') else patient_code end,
    first_name=case when _changes ? 'first_name' then nullif(pg_catalog.btrim(_changes->>'first_name'),'') else first_name end,
    last_name=case when _changes ? 'last_name' then nullif(pg_catalog.btrim(_changes->>'last_name'),'') else last_name end,
    date_of_birth=case when _changes ? 'date_of_birth' then nullif(_changes->>'date_of_birth','')::date else date_of_birth end,
    gender=case when _changes ? 'gender' then nullif(_changes->>'gender','') else gender end,
    email=case when _changes ? 'email' then nullif(_changes->>'email','') else email end,
    phone=case when _changes ? 'phone' then nullif(_changes->>'phone','') else phone end,
    address=case when _changes ? 'address' then nullif(_changes->>'address','') else address end,
    city=case when _changes ? 'city' then nullif(_changes->>'city','') else city end,
    ghana_card_number=case when _changes ? 'ghana_card_number' then nullif(_changes->>'ghana_card_number','') else ghana_card_number end,
    insurance_provider=case when _changes ? 'insurance_provider' then nullif(_changes->>'insurance_provider','') else insurance_provider end,
    insurance_number=case when _changes ? 'insurance_number' then nullif(_changes->>'insurance_number','') else insurance_number end,
    insurance_group_number=case when _changes ? 'insurance_group_number' then nullif(_changes->>'insurance_group_number','') else insurance_group_number end,
    insurance_expiry=case when _changes ? 'insurance_expiry' then nullif(_changes->>'insurance_expiry','')::date else insurance_expiry end,
    emergency_contact_name=case when _changes ? 'emergency_contact_name' then nullif(_changes->>'emergency_contact_name','') else emergency_contact_name end,
    emergency_contact_phone=case when _changes ? 'emergency_contact_phone' then nullif(_changes->>'emergency_contact_phone','') else emergency_contact_phone end,
    emergency_contact_relation=case when _changes ? 'emergency_contact_relation' then nullif(_changes->>'emergency_contact_relation','') else emergency_contact_relation end,
    blood_group=case when _changes ? 'blood_group' then nullif(_changes->>'blood_group','') else blood_group end,
    genotype=case when _changes ? 'genotype' then nullif(_changes->>'genotype','') else genotype end,
    allergies=case when _changes ? 'allergies' then nullif(_changes->>'allergies','') else allergies end,
    chronic_conditions=case when _changes ? 'chronic_conditions' then nullif(_changes->>'chronic_conditions','') else chronic_conditions end,
    status=case when _changes ? 'status' then nullif(_changes->>'status','') else status end,
    updated_at=now()
  where id=_patient_id
  returning * into v_patient;
  return v_patient;
end;
$function$;
REVOKE ALL ON FUNCTION public.update_patient_workflow(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_patient_workflow(uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.transition_emergency_case(_case_id uuid,_status text,_disposition text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE uid uuid:=auth.uid(); c public.emergency_cases%ROWTYPE;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN('waiting','triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled') THEN RAISE EXCEPTION 'Invalid emergency status'; END IF;
 SELECT * INTO c FROM public.emergency_cases WHERE id=_case_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Emergency case not found'; END IF;
 PERFORM public.assert_patient_facility_context(c.patient_id);
 IF c.facility_id IS DISTINCT FROM (SELECT p.facility_id FROM public.patients p WHERE p.id=c.patient_id) THEN RAISE EXCEPTION 'Emergency case facility does not match patient facility'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=c.patient_id) THEN RAISE EXCEPTION 'Emergency patient not found'; END IF;
 IF c.status IN('discharged','referred','left_without_being_seen','cancelled') AND _status<>c.status THEN RAISE EXCEPTION 'Closed emergency case cannot be reopened'; END IF;
 IF c.status='waiting' AND _status NOT IN('waiting','triage','cancelled','left_without_being_seen') THEN RAISE EXCEPTION 'Emergency case must be triaged before treatment'; END IF;
 IF c.status='triage' AND _status NOT IN('triage','treatment','observation','admitted','referred','cancelled') THEN RAISE EXCEPTION 'Invalid emergency transition from triage'; END IF;
 IF _status IN('discharged','referred','left_without_being_seen','cancelled') AND NULLIF(btrim(COALESCE(_disposition,'')),'') IS NULL THEN RAISE EXCEPTION 'Disposition is required when closing an emergency case'; END IF;
 UPDATE public.emergency_cases SET status=_status,disposition=COALESCE(NULLIF(btrim(_disposition),''),disposition),assigned_officer=COALESCE(assigned_officer,uid),updated_at=now() WHERE id=c.id;
 PERFORM public.record_system_audit('emergency_case_transition','emergency','emergency_case',c.id,'info',jsonb_build_object('patient_id',c.patient_id,'from_status',c.status,'to_status',_status,'disposition',_disposition));
 RETURN jsonb_build_object('case_id',c.id,'status',_status);
END; $function$;
REVOKE ALL ON FUNCTION public.transition_emergency_case(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.transition_emergency_case(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.start_imaging_order(_imaging_order_id uuid)
RETURNS public.imaging_orders LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE uid uuid:=auth.uid(); o public.imaging_orders; s public.service_orders; es text;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'radiologist') OR public.has_role(uid,'radiology_technician')) THEN RAISE EXCEPTION 'Radiology operational role required'; END IF;
 SELECT * INTO o FROM public.imaging_orders WHERE id=_imaging_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
 PERFORM public.assert_patient_facility_context(o.patient_id);
 IF o.facility_id IS DISTINCT FROM (SELECT p.facility_id FROM public.patients p WHERE p.id=o.patient_id) THEN RAISE EXCEPTION 'Imaging order facility does not match patient facility'; END IF;
 IF o.status <> 'released' THEN RAISE EXCEPTION 'Imaging order must be released before it can start'; END IF;
 IF o.encounter_id IS NOT NULL THEN
   SELECT status INTO es FROM public.encounters WHERE id=o.encounter_id;
   IF es IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot start imaging for a closed encounter'; END IF;
 END IF;
 IF o.service_order_id IS NULL THEN
   UPDATE public.imaging_orders SET status='in_progress',performed_by=uid,updated_at=now() WHERE id=o.id RETURNING * INTO o;
   RETURN o;
 END IF;
 SELECT * INTO s FROM public.service_orders WHERE id=o.service_order_id FOR UPDATE;
 IF NOT FOUND OR s.patient_id<>o.patient_id OR s.facility_id IS DISTINCT FROM o.facility_id OR s.related_entity_id<>o.id OR s.department<>'imaging' THEN RAISE EXCEPTION 'Imaging service order linkage is invalid'; END IF;
 IF s.status<>'released' THEN RAISE EXCEPTION 'Linked service order must be released before imaging can start'; END IF;
 UPDATE public.service_orders SET status='in_progress',started_at=COALESCE(started_at,now()),updated_at=now() WHERE id=s.id;
 UPDATE public.department_queues SET status='claimed',claimed_by=uid,assigned_to=uid,claimed_at=COALESCE(claimed_at,now()),updated_at=now() WHERE service_order_id=s.id;
 UPDATE public.imaging_orders SET status='in_progress',performed_by=uid,updated_at=now() WHERE id=o.id RETURNING * INTO o;
 RETURN o;
END; $function$;
REVOKE ALL ON FUNCTION public.start_imaging_order(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.start_imaging_order(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
