-- Read-only inpatient discharge billing projection.
-- Billing materialization remains explicit in the existing preparation workflow.

create or replace function public.get_inpatient_discharge_bill(
  _patient_id uuid,
  _admission_id uuid,
  _to timestamptz default now()
)
returns table(
  admission_id uuid,
  patient_id uuid,
  invoice_id uuid,
  invoice_item_id uuid,
  source_type text,
  source_id uuid,
  description text,
  category text,
  department text,
  quantity integer,
  unit_price numeric,
  amount numeric,
  paid_amount numeric,
  outstanding_amount numeric,
  service_order_id uuid,
  service_order_status text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  uid uuid := auth.uid();
  v_role text;
  v_facility uuid;
  v_admission public.admissions%rowtype;
begin
  if uid is null then raise exception 'Authentication required'; end if;

  select case
    when public.has_role(uid,'system_superuser'::public.app_role) then 'system_superuser'
    when public.has_role(uid,'admin'::public.app_role) then 'admin'
    when public.has_role(uid,'it_admin'::public.app_role) then 'it_admin'
    when public.has_role(uid,'accountant'::public.app_role) then 'accountant'
    when public.has_role(uid,'front_desk'::public.app_role) then 'front_desk'
    else null
  end into v_role;

  if v_role is null then raise exception 'Inpatient billing access is not permitted'; end if;

  select * into v_admission
  from public.admissions
  where id = _admission_id and patient_id = _patient_id;

  if v_admission.id is null then raise exception 'Admission not found for patient'; end if;

  v_facility := public.assert_patient_facility_context(_patient_id);

  if v_role not in ('system_superuser','admin','it_admin') and v_admission.facility_id is distinct from v_facility then
    raise exception 'Admission facility context does not match the active facility';
  end if;

  return query
  with admission_items as (
    select ii.id, ii.invoice_id, ii.source_type, ii.source_id, ii.description,
           ii.category, ii.department, ii.quantity, ii.unit_price, ii.amount,
           ii.created_at, ii.service_order_id
    from public.invoice_items ii
    join public.invoices i on i.id = ii.invoice_id
    where i.patient_id = _patient_id
      and (_to is null or ii.created_at <= _to)
      and (
        (ii.source_type = 'admission' and ii.source_id = _admission_id)
        or exists (
          select 1
          from public.service_orders so
          left join public.encounters e on e.id = so.encounter_id
          where so.id = coalesce(ii.service_order_id, ii.source_id)
            and so.patient_id = _patient_id
            and so.created_at >= v_admission.admitted_at
            and so.created_at <= coalesce(v_admission.discharged_at, _to, now())
            and (e.admission_id = _admission_id or so.related_entity_id = _admission_id)
        )
        or exists (
          select 1
          from public.encounters e
          where e.id = ii.source_id and e.admission_id = _admission_id
        )
      )
  )
  select _admission_id, _patient_id, ai.invoice_id, ai.id, ai.source_type, ai.source_id,
         ai.description, ai.category, ai.department, ai.quantity, ai.unit_price, ai.amount,
         coalesce((select sum(ip.amount) from public.invoice_item_payments ip where ip.invoice_item_id = ai.id),0),
         greatest(ai.amount - coalesce((select sum(ip.amount) from public.invoice_item_payments ip where ip.invoice_item_id = ai.id),0),0),
         so.id, so.status, ai.created_at
  from admission_items ai
  left join lateral (
    select s.id, s.status
    from public.service_orders s
    where s.id = coalesce(ai.service_order_id, ai.source_id)
    order by s.created_at desc
    limit 1
  ) so on true
  order by ai.created_at;
end;
$function$;

revoke execute on function public.get_inpatient_discharge_bill(uuid,uuid,timestamptz) from public, anon;
grant execute on function public.get_inpatient_discharge_bill(uuid,uuid,timestamptz) to authenticated;
