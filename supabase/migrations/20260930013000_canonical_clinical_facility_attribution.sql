-- Canonical facility attribution for clinical transaction data.
-- Existing rows remain nullable until explicitly reconciled.
alter table public.patients add column if not exists facility_id uuid references public.healthcare_facilities(id);
alter table public.encounters add column if not exists facility_id uuid references public.healthcare_facilities(id);
alter table public.service_orders add column if not exists facility_id uuid references public.healthcare_facilities(id);
alter table public.department_queues add column if not exists facility_id uuid references public.healthcare_facilities(id);
alter table public.lab_orders add column if not exists facility_id uuid references public.healthcare_facilities(id);
alter table public.lab_results add column if not exists facility_id uuid references public.healthcare_facilities(id);
alter table public.imaging_orders add column if not exists facility_id uuid references public.healthcare_facilities(id);
alter table public.prescriptions add column if not exists facility_id uuid references public.healthcare_facilities(id);
alter table public.diagnoses add column if not exists facility_id uuid references public.healthcare_facilities(id);

create index if not exists patients_facility_id_idx on public.patients(facility_id);
create index if not exists encounters_facility_id_idx on public.encounters(facility_id);
create index if not exists service_orders_facility_id_idx on public.service_orders(facility_id);
create index if not exists department_queues_facility_id_idx on public.department_queues(facility_id);
create index if not exists lab_orders_facility_id_idx on public.lab_orders(facility_id);
create index if not exists lab_results_facility_id_idx on public.lab_results(facility_id);
create index if not exists imaging_orders_facility_id_idx on public.imaging_orders(facility_id);
create index if not exists prescriptions_facility_id_idx on public.prescriptions(facility_id);
create index if not exists diagnoses_facility_id_idx on public.diagnoses(facility_id);

create or replace function public.assign_active_facility()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_facility uuid;
begin
  v_facility := public.current_user_facility_id();
  if v_facility is null then raise exception 'An active facility is required for clinical transaction writes'; end if;
  if new.facility_id is null then new.facility_id := v_facility;
  elsif new.facility_id <> v_facility then raise exception 'Facility context mismatch'; end if;
  return new;
end $$;
revoke all on function public.assign_active_facility() from public, anon, authenticated;

create or replace function public.sync_child_facility_from_parent()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_facility uuid;
begin
  if tg_table_name='department_queues' then
    select so.facility_id into v_facility from public.service_orders so where so.id=new.service_order_id;
  elsif tg_table_name='lab_orders' then
    select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id;
    if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
  elsif tg_table_name='lab_results' then
    select lo.facility_id into v_facility from public.lab_orders lo where lo.id=new.lab_order_id;
  elsif tg_table_name='imaging_orders' then
    select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id;
    if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
  elsif tg_table_name='prescriptions' then
    select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id;
    if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
  elsif tg_table_name='diagnoses' then
    select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id;
    if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
  end if;
  if v_facility is null then raise exception 'Parent clinical record has no facility attribution'; end if;
  if new.facility_id is null then new.facility_id:=v_facility;
  elsif new.facility_id<>v_facility then raise exception 'Facility lineage mismatch'; end if;
  return new;
end $$;
revoke all on function public.sync_child_facility_from_parent() from public, anon, authenticated;

drop trigger if exists patients_assign_active_facility on public.patients;
create trigger patients_assign_active_facility before insert on public.patients for each row execute function public.assign_active_facility();
drop trigger if exists encounters_assign_active_facility on public.encounters;
create trigger encounters_assign_active_facility before insert on public.encounters for each row execute function public.assign_active_facility();
drop trigger if exists service_orders_assign_active_facility on public.service_orders;
create trigger service_orders_assign_active_facility before insert on public.service_orders for each row execute function public.assign_active_facility();

drop trigger if exists department_queues_sync_facility on public.department_queues;
create trigger department_queues_sync_facility before insert on public.department_queues for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists lab_orders_sync_facility on public.lab_orders;
create trigger lab_orders_sync_facility before insert on public.lab_orders for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists lab_results_sync_facility on public.lab_results;
create trigger lab_results_sync_facility before insert on public.lab_results for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists imaging_orders_sync_facility on public.imaging_orders;
create trigger imaging_orders_sync_facility before insert on public.imaging_orders for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists prescriptions_sync_facility on public.prescriptions;
create trigger prescriptions_sync_facility before insert on public.prescriptions for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists diagnoses_sync_facility on public.diagnoses;
create trigger diagnoses_sync_facility before insert on public.diagnoses for each row execute function public.sync_child_facility_from_parent();

-- Prevent facility attribution from being cleared or changed outside the active context.
create or replace function public.assign_active_facility()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_facility uuid;
begin
  v_facility := public.current_user_facility_id();
  if v_facility is null then raise exception 'An active facility is required for clinical transaction writes'; end if;
  if new.facility_id is null then
    if tg_op='UPDATE' then raise exception 'Facility attribution cannot be cleared'; end if;
    new.facility_id:=v_facility;
  elsif new.facility_id<>v_facility and not (public.current_user_has_role('admin') or public.current_user_has_role('it_admin')) then
    raise exception 'Facility context mismatch';
  end if;
  return new;
end $$;

drop trigger if exists patients_assign_active_facility on public.patients;
create trigger patients_assign_active_facility before insert or update of facility_id on public.patients for each row execute function public.assign_active_facility();
drop trigger if exists encounters_assign_active_facility on public.encounters;
create trigger encounters_assign_active_facility before insert or update of facility_id on public.encounters for each row execute function public.assign_active_facility();
drop trigger if exists service_orders_assign_active_facility on public.service_orders;
create trigger service_orders_assign_active_facility before insert or update of facility_id on public.service_orders for each row execute function public.assign_active_facility();

create or replace function public.sync_child_facility_from_parent()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_facility uuid;
begin
  if tg_table_name='department_queues' then
    select so.facility_id into v_facility from public.service_orders so where so.id=new.service_order_id;
  elsif tg_table_name='lab_orders' then
    select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id;
    if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
  elsif tg_table_name='lab_results' then
    select lo.facility_id into v_facility from public.lab_orders lo where lo.id=new.lab_order_id;
  elsif tg_table_name='imaging_orders' then
    select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id;
    if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
  elsif tg_table_name='prescriptions' then
    select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id;
    if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
  elsif tg_table_name='diagnoses' then
    select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id;
    if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
  end if;
  if v_facility is null then raise exception 'Parent clinical record has no facility attribution'; end if;
  if new.facility_id is null then
    if tg_op='UPDATE' then raise exception 'Facility attribution cannot be cleared'; end if;
    new.facility_id:=v_facility;
  elsif new.facility_id<>v_facility then raise exception 'Facility lineage mismatch'; end if;
  return new;
end $$;

drop trigger if exists department_queues_sync_facility on public.department_queues;
create trigger department_queues_sync_facility before insert or update of facility_id on public.department_queues for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists lab_orders_sync_facility on public.lab_orders;
create trigger lab_orders_sync_facility before insert or update of facility_id on public.lab_orders for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists lab_results_sync_facility on public.lab_results;
create trigger lab_results_sync_facility before insert or update of facility_id on public.lab_results for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists imaging_orders_sync_facility on public.imaging_orders;
create trigger imaging_orders_sync_facility before insert or update of facility_id on public.imaging_orders for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists prescriptions_sync_facility on public.prescriptions;
create trigger prescriptions_sync_facility before insert or update of facility_id on public.prescriptions for each row execute function public.sync_child_facility_from_parent();
drop trigger if exists diagnoses_sync_facility on public.diagnoses;
create trigger diagnoses_sync_facility before insert or update of facility_id on public.diagnoses for each row execute function public.sync_child_facility_from_parent();

create policy "facility scope preserves assigned clinical rows"
on public.encounters as restrictive for select to authenticated
using (facility_id is null or public.current_user_has_facility_access(facility_id));
create policy "facility scope preserves assigned lab orders"
on public.lab_orders as restrictive for select to authenticated
using (facility_id is null or public.current_user_has_facility_access(facility_id));
create policy "facility scope preserves assigned imaging orders"
on public.imaging_orders as restrictive for select to authenticated
using (facility_id is null or public.current_user_has_facility_access(facility_id));
create policy "facility scope preserves assigned service orders"
on public.service_orders as restrictive for select to authenticated
using (facility_id is null or public.current_user_has_facility_access(facility_id));
create policy "facility scope preserves assigned queues"
on public.department_queues as restrictive for select to authenticated
using (facility_id is null or public.current_user_has_facility_access(facility_id));
create policy "facility scope preserves assigned prescriptions"
on public.prescriptions as restrictive for select to authenticated
using (facility_id is null or public.current_user_has_facility_access(facility_id));
create policy "facility scope preserves assigned diagnoses"
on public.diagnoses as restrictive for select to authenticated
using (facility_id is null or public.current_user_has_facility_access(facility_id));
create policy "facility scope preserves assigned patients"
on public.patients as restrictive for select to authenticated
using (facility_id is null or public.current_user_has_facility_access(facility_id));