-- Reconcile encounter completion with server-authoritative billing materialization.
-- Clinical users may materialize billing only for their own encounter; billing roles retain patient-wide preparation.
CREATE OR REPLACE FUNCTION public.prepare_patient_billable_items(_patient_id uuid, _from timestamp with time zone DEFAULT date_trunc('day'::text, now()), _to timestamp with time zone DEFAULT now())
 RETURNS TABLE(invoice_id uuid, invoice_item_id uuid, source_type text, source_id uuid, description text, category text, department text, quantity integer, unit_price numeric, amount numeric, paid_amount numeric, outstanding_amount numeric, service_order_id uuid, service_order_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE inv uuid; tariff numeric; r record; days_count integer; uid uuid:=auth.uid(); v_patient_facility uuid; v_invoice_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'front_desk') THEN
    NULL;
  ELSIF public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.encounters e
      WHERE e.patient_id=_patient_id
        AND e.practitioner_id=uid
        AND e.created_at<=_to
        AND (e.completed_at IS NULL OR e.completed_at>=_from)
    ) THEN RAISE EXCEPTION 'Billing materialization is limited to the clinician''s own encounter'; END IF;
  ELSE
    RAISE EXCEPTION 'Billing access denied';
  END IF;
  IF _patient_id IS NULL OR _from IS NULL OR _to IS NULL OR _from>_to THEN RAISE EXCEPTION 'Invalid patient billing period'; END IF;
  v_patient_facility := public.assert_patient_facility_context(_patient_id);
  PERFORM pg_advisory_xact_lock(pg_catalog.hashtextextended(_patient_id::text,0));
  SELECT id,facility_id INTO inv,v_invoice_facility FROM public.invoices WHERE patient_id=_patient_id AND status IN('pending','partially_paid') ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF inv IS NOT NULL THEN
    IF v_invoice_facility IS NULL THEN RAISE EXCEPTION 'Invoice facility attribution is unresolved'; END IF;
    IF v_invoice_facility IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION 'Invoice and patient facility context do not match'; END IF;
  ELSE
    INSERT INTO public.invoices(invoice_number,patient_id,total_amount,created_by,facility_id)
    VALUES('INV-'||pg_catalog.to_char(pg_catalog.clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||pg_catalog.substr(gen_random_uuid()::text,1,6),_patient_id,0,uid,v_patient_facility)
    RETURNING id INTO inv;
  END IF;
  SELECT st.amount INTO tariff FROM public.service_tariffs st WHERE st.service_code='CONSULTATION' AND st.active AND st.effective_from<=_to::date AND (st.effective_to IS NULL OR st.effective_to>=_from::date) ORDER BY st.effective_from DESC NULLS LAST LIMIT 1;
  IF tariff IS NOT NULL THEN
    INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,service_code,department)
    SELECT inv,'Consultation',1,tariff,tariff,'consultation','appointment',a.id,'CONSULTATION','consultation' FROM public.appointments a
    WHERE a.patient_id=_patient_id AND a.scheduled_at BETWEEN _from AND _to AND a.status NOT IN('cancelled','no_show')
      AND NOT EXISTS(select 1 from public.invoice_items i where i.source_type='appointment' and i.source_id=a.id)
      AND NOT EXISTS(select 1 from public.service_orders so where so.patient_id=a.patient_id and so.related_entity_id=a.id and so.department='consultation' and so.status<>'cancelled');
  END IF;
  SELECT st.amount INTO tariff FROM public.service_tariffs st WHERE st.service_code='LAB-GENERIC' AND st.active AND st.effective_from<=_to::date AND (st.effective_to IS NULL OR st.effective_to>=_from::date) ORDER BY st.effective_from DESC NULLS LAST LIMIT 1;
  IF tariff IS NOT NULL THEN
    FOR r IN SELECT l.id,l.test_name FROM public.lab_orders l WHERE l.patient_id=_patient_id AND l.created_at BETWEEN _from AND _to AND l.status<>'cancelled'
      AND NOT EXISTS(select 1 from public.service_orders so where so.patient_id=l.patient_id and so.related_entity_id=l.id and so.department='laboratory' and so.status<>'cancelled')
    LOOP
      INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,service_code,department)
      SELECT inv,r.test_name,1,tariff,tariff,'lab','lab_order',r.id,'LAB-GENERIC','laboratory'
      WHERE NOT EXISTS(select 1 from public.invoice_items i where i.source_type='lab_order' and i.source_id=r.id);
    END LOOP;
  END IF;
  SELECT st.amount INTO tariff FROM public.service_tariffs st WHERE st.service_code='PROCEDURE-GENERIC' AND st.active AND st.effective_from<=_to::date AND (st.effective_to IS NULL OR st.effective_to>=_from::date) ORDER BY st.effective_from DESC NULLS LAST LIMIT 1;
  FOR r IN SELECT so.id,so.service_name,so.amount,so.department,so.service_code,so.quantity FROM public.service_orders so WHERE so.patient_id=_patient_id AND so.created_at BETWEEN _from AND _to AND so.status<>'cancelled'
  LOOP
    INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,service_code,department)
    SELECT inv,r.service_name,pg_catalog.greatest(pg_catalog.coalesce(r.quantity,1),1),pg_catalog.coalesce(NULLIF(r.amount,0),tariff,0),pg_catalog.coalesce(NULLIF(r.amount,0),tariff,0)*pg_catalog.greatest(pg_catalog.coalesce(r.quantity,1),1),
      case when r.department='pharmacy' then 'pharmacy' when r.department='laboratory' then 'lab' when r.department in('imaging','radiology') then 'imaging' else 'procedure' end,
      'service_order',r.id,pg_catalog.coalesce(r.service_code,'PROCEDURE-GENERIC'),r.department
    WHERE NOT EXISTS(select 1 from public.invoice_items i where i.source_type='service_order' and i.source_id=r.id);
  END LOOP;
  SELECT st.amount INTO tariff FROM public.service_tariffs st WHERE st.service_code='PROCEDURE-GENERIC' AND st.active AND st.effective_from<=_to::date AND (st.effective_to IS NULL OR st.effective_to>=_from::date) ORDER BY st.effective_from DESC NULLS LAST LIMIT 1;
  IF tariff IS NOT NULL THEN
    FOR r IN SELECT p.id,p.medication,p.computed_quantity FROM public.prescriptions p WHERE p.patient_id=_patient_id AND p.created_at BETWEEN _from AND _to AND p.status<>'cancelled'
      AND NOT EXISTS(select 1 from public.service_orders so where so.patient_id=p.patient_id and so.related_entity_id=p.id and so.department='pharmacy' and so.status<>'cancelled')
    LOOP
      INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,service_code,department)
      SELECT inv,'Medication: '||r.medication,pg_catalog.greatest(pg_catalog.coalesce(NULLIF(r.computed_quantity,0),1),1),tariff,pg_catalog.greatest(pg_catalog.coalesce(NULLIF(r.computed_quantity,0),1),1)*tariff,'pharmacy','prescription',r.id,'PROCEDURE-GENERIC','pharmacy'
      WHERE NOT EXISTS(select 1 from public.invoice_items i where i.source_type='prescription' and i.source_id=r.id);
    END LOOP;
  END IF;
  SELECT st.amount INTO tariff FROM public.service_tariffs st WHERE st.service_code='WARD-ACCOM' AND st.active AND st.effective_from<=_to::date AND (st.effective_to IS NULL OR st.effective_to>=_from::date) ORDER BY st.effective_from DESC NULLS LAST LIMIT 1;
  IF tariff IS NOT NULL AND to_regclass('public.admissions') IS NOT NULL THEN
    FOR r IN SELECT a.id,a.admitted_at,a.discharged_at,a.ward FROM public.admissions a WHERE a.patient_id=_patient_id AND a.admitted_at<=_to AND pg_catalog.coalesce(a.discharged_at,_to)>=_from
    LOOP
      days_count:=pg_catalog.greatest(1,pg_catalog.ceil(extract(epoch from(pg_catalog.least(pg_catalog.coalesce(r.discharged_at,_to),_to)-pg_catalog.greatest(r.admitted_at,_from)))/86400)::integer);
      INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,service_code,department)
      SELECT inv,'Accommodation: '||pg_catalog.coalesce(r.ward,'Ward'),days_count,tariff,days_count*tariff,'ward','admission',r.id,'WARD-ACCOM','ward'
      WHERE NOT EXISTS(select 1 from public.invoice_items i where i.source_type='admission' and i.source_id=r.id);
    END LOOP;
  END IF;
  UPDATE public.invoices SET total_amount=pg_catalog.coalesce((select sum(ii.amount) from public.invoice_items ii where ii.invoice_id=inv),0),updated_at=pg_catalog.now() WHERE id=inv;
  RETURN QUERY SELECT ii.invoice_id,ii.id,ii.source_type,ii.source_id,ii.description,ii.category,ii.department,ii.quantity,ii.unit_price,ii.amount,
    pg_catalog.coalesce((select sum(ip.amount) from public.invoice_item_payments ip where ip.invoice_item_id=ii.id),0),
    pg_catalog.greatest(ii.amount-pg_catalog.coalesce((select sum(ip.amount) from public.invoice_item_payments ip where ip.invoice_item_id=ii.id),0),0),
    so.id,so.status
  FROM public.invoice_items ii
  LEFT JOIN LATERAL(select s.id,s.status from public.service_orders s where s.invoice_item_id=ii.id order by s.created_at desc limit 1)so on true
  WHERE ii.invoice_id=inv ORDER BY ii.created_at;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.submit_encounter_workflow(_encounter_id uuid, _specialty text DEFAULT NULL::text, _appointment_date timestamp with time zone DEFAULT NULL::timestamp with time zone, _referral_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_enc public.encounters%rowtype; v_referral uuid; v_snapshot jsonb; v_version integer; v_require_principal boolean:=true; v_patient_facility uuid; v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 select * into v_enc from public.encounters where id=_encounter_id for update;
 if v_enc.id is null then raise exception 'Encounter not found'; end if;
 perform public.ensure_encounter_facility_attribution(_encounter_id);
 select * into v_enc from public.encounters where id=_encounter_id for update;
 v_patient_facility:=public.assert_patient_facility_context(v_enc.patient_id);
 if v_enc.facility_id is null then raise exception 'Encounter facility attribution is unresolved'; end if;
 if v_enc.facility_id is distinct from v_patient_facility then raise exception 'Encounter or patient belongs to a different facility context'; end if;
 if v_enc.practitioner_id<>v_uid and not public.has_role(v_uid,'admin') and not public.has_role(v_uid,'it_admin') and not public.has_role(v_uid,'system_superuser') then raise exception 'Only the encounter creator can submit this document'; end if;
 if v_enc.status='completed' then raise exception 'Encounter is already submitted'; end if;
 select coalesce(require_principal_diagnosis_for_final,true) into v_require_principal from public.facility_configuration order by created_at asc limit 1;
 if v_require_principal and not exists(select 1 from public.diagnoses d where d.encounter_id=v_enc.id and d.is_principal=true) then raise exception 'Principal diagnosis required before final submission'; end if;
 if nullif(pg_catalog.btrim(v_enc.treatment_plan),'') is null and exists(select 1 from public.prescriptions p where p.encounter_id=v_enc.id) then raise exception 'Treatment plan is required when prescriptions are documented'; end if;
 if nullif(pg_catalog.btrim(_specialty),'') is not null then
  if _appointment_date is null then raise exception 'Referral appointment date is required'; end if;
  insert into public.patient_referrals(patient_id,encounter_id,referred_by,destination,specialty,reason,urgency,status,clinical_summary,appointment_date,facility_id)
  values(v_enc.patient_id,v_enc.id,v_uid,'Specialist Clinic',pg_catalog.btrim(_specialty),coalesce(nullif(pg_catalog.btrim(_referral_reason),''),'Specialist review requested'),'routine','requested',coalesce(v_enc.treatment_plan,v_enc.principal_diagnosis),_appointment_date,v_patient_facility) returning id into v_referral;
 end if;
 v_version:=greatest(coalesce(v_enc.version_no,1),1);
 v_snapshot:=jsonb_build_object('encounter',to_jsonb(v_enc),'diagnoses',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at,d.id) from public.diagnoses d where d.encounter_id=v_enc.id),'[]'::jsonb),'prescriptions',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at,p.id) from public.prescriptions p where p.encounter_id=v_enc.id),'[]'::jsonb),'referral_id',v_referral,'workflow_requirements',jsonb_build_object('require_principal_diagnosis',v_require_principal));
 update public.encounters set status='completed',submitted_at=pg_catalog.now(),submitted_by=v_uid,locked_at=pg_catalog.now(),version_no=v_version,updated_at=pg_catalog.now() where id=_encounter_id;
  PERFORM public.prepare_patient_billable_items(v_enc.patient_id,pg_catalog.date_trunc('day',v_enc.created_at),coalesce(v_enc.completed_at,pg_catalog.now()));
 insert into public.document_versions(entity_type,entity_id,version_no,action,snapshot,changed_by) values('encounter',v_enc.id,v_version,'submitted',v_snapshot,v_uid) on conflict(entity_type,entity_id,version_no,action) do nothing;
 perform public.record_system_audit('encounter_submitted','clinical','encounter',v_enc.id,'info',jsonb_build_object('patient_id',v_enc.patient_id,'version_no',v_version,'referral_id',v_referral,'require_principal_diagnosis',v_require_principal));
 return jsonb_build_object('encounter_id',v_enc.id,'status','completed','version_no',v_version,'referral_id',v_referral,'require_principal_diagnosis',v_require_principal);
end;$function$

;

REVOKE ALL ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.submit_encounter_workflow(uuid,text,timestamptz,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.submit_encounter_workflow(uuid,text,timestamptz,text) TO authenticated;
NOTIFY pgrst,'reload schema';