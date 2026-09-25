alter table public.lab_orders
  add column if not exists encounter_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='lab_orders_encounter_id_fkey'
      and conrelid='public.lab_orders'::regclass
  ) then
    alter table public.lab_orders
      add constraint lab_orders_encounter_id_fkey
      foreign key (encounter_id) references public.encounters(id) on delete set null;
  end if;
end $$;

create index if not exists idx_lab_orders_encounter_id on public.lab_orders(encounter_id);

create or replace function public.create_lab_order_with_payment_gate(
  _patient_id uuid,
  _test_name text,
  _test_category text default null,
  _priority text default 'routine',
  _clinical_notes text default null,
  _amount numeric default 0,
  _encounter_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_lab_order_id uuid;
  v_service_order_id uuid;
  v_requires_payment boolean := coalesce(_amount,0) > 0;
  v_service_status text := case when v_requires_payment then 'pending_payment_approval' else 'released' end;
begin
  if v_uid is null then raise exception 'Authentication is required'; end if;
  if not (
    public.has_role(v_uid,'admin') or public.has_role(v_uid,'practitioner')
    or public.has_role(v_uid,'nurse') or public.has_role(v_uid,'midwife')
    or public.has_role(v_uid,'lab_technician') or public.has_role(v_uid,'front_desk')
  ) then raise exception 'Laboratory order access required'; end if;
  if _patient_id is null or nullif(btrim(_test_name),'') is null then
    raise exception 'Patient and test name are required';
  end if;
  if coalesce(_amount,0) < 0 then raise exception 'Amount cannot be negative'; end if;
  if not exists (select 1 from public.patients where id=_patient_id) then
    raise exception 'Patient not found';
  end if;
  if _encounter_id is not null and not exists (
    select 1 from public.encounters
    where id=_encounter_id and patient_id=_patient_id and status not in ('cancelled')
  ) then
    raise exception 'Selected encounter does not belong to the patient or is not available';
  end if;

  insert into public.lab_orders(patient_id,encounter_id,test_name,test_category,priority,status,clinical_notes,ordered_by)
  values(_patient_id,_encounter_id,btrim(_test_name),nullif(btrim(_test_category),''),coalesce(nullif(btrim(_priority),''),'routine'),'ordered',nullif(btrim(_clinical_notes),''),v_uid)
  returning id into v_lab_order_id;

  insert into public.service_orders(patient_id,encounter_id,department,service_name,amount,unit_price,payment_required,status,requested_by,created_by,related_entity_id,order_type,service_code,notes)
  values(_patient_id,_encounter_id,'laboratory',btrim(_test_name),coalesce(_amount,0),coalesce(_amount,0),v_requires_payment,v_service_status,v_uid,v_uid,v_lab_order_id,'lab',nullif(btrim(_test_category),''),nullif(btrim(_clinical_notes),'')) 
  returning id into v_service_order_id;

  return jsonb_build_object('lab_order_id',v_lab_order_id,'service_order_id',v_service_order_id,'encounter_id',_encounter_id,'status',v_service_status);
end;
$function$;

drop function if exists public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric);

revoke all on function public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid) from public, anon;
grant execute on function public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid) to authenticated;

create or replace function public.approve_lab_result(_lab_result_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); r public.lab_results%rowtype; o public.lab_orders%rowtype;
begin
 if uid is null or not (public.has_role(uid,'admin') or public.has_role(uid,'lab_technician') or public.has_role(uid,'practitioner')) then raise exception 'Laboratory approval role required'; end if;
 select * into r from public.lab_results where id=_lab_result_id for update;
 if not found then raise exception 'Laboratory result not found'; end if;
 if r.status<>'completed' then raise exception 'Only completed results can be approved'; end if;
 select * into o from public.lab_orders where id=r.lab_order_id for update;
 if not found then raise exception 'Laboratory order not found'; end if;
 if o.status<>'completed' then raise exception 'Laboratory order must be completed before result approval'; end if;
 update public.lab_results set status='approved',approved_by=uid,approved_at=now(),updated_at=now() where id=r.id and status='completed';
 update public.lab_orders set status='approved',updated_at=now() where id=o.id and status='completed';
 if o.ordered_by is not null and not exists (
   select 1 from public.notifications where recipient_user_id=o.ordered_by and related_entity_id=o.id and category='diagnostic_result' and title='Laboratory result ready' and is_read=false
 ) then
   insert into public.notifications(recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
   values(o.ordered_by,'Laboratory result ready',format('The %s laboratory result is approved and ready for clinical review.',o.test_name),
     case when coalesce(r.is_abnormal,false) then 'critical' else 'info' end,'diagnostic_result','/encounters',o.patient_id,o.id,
     jsonb_build_object('workflow','lab_result_review','lab_result_id',r.id,'lab_order_id',o.id,'encounter_id',o.encounter_id,'is_abnormal',coalesce(r.is_abnormal,false),'requires_acknowledgement',true));
 end if;
 return jsonb_build_object('lab_result_id',r.id,'lab_order_id',o.id,'encounter_id',o.encounter_id,'status','approved');
end;
$function$;

revoke all on function public.approve_lab_result(uuid) from public, anon;
grant execute on function public.approve_lab_result(uuid) to authenticated;
