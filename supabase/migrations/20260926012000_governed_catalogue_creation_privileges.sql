-- Governed catalogue creation privileges.
create or replace function public.current_user_has_catalogue_create_permission(_permission text)
returns boolean language sql stable security definer set search_path=public as $$
  select auth.uid() is not null and (
    public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'it_admin') or
    exists (select 1 from public.user_roles ur join public.role_permissions rp on rp.role=ur.role and rp.permission_key=_permission join public.permissions p on p.permission_key=rp.permission_key and p.is_active where ur.user_id=auth.uid())
  );
$$;
revoke all on function public.current_user_has_catalogue_create_permission(text) from public,anon,authenticated;

create or replace function public.create_service_catalogue_item(_service_code text,_service_name text,_department text,_unit text,_amount numeric,_currency text default 'GHS')
returns public.service_tariffs language plpgsql security definer set search_path=public as $$
declare r public.service_tariffs; uid uuid:=auth.uid(); actor_department text; target_department text:=lower(trim(coalesce(_department,'')));
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not public.current_user_has_catalogue_create_permission('create_services') then raise exception 'Create services privilege required'; end if;
  select lower(trim(coalesce(p.department,''))) into actor_department from public.profiles p where p.id=uid;
  if not (public.has_role(uid,'admin') or public.has_role(uid,'it_admin')) and (target_department='' or actor_department='' or target_department<>actor_department) then raise exception 'You may create services only for your department'; end if;
  if length(trim(coalesce(_service_code,'')))<2 then raise exception 'Service code is required'; end if;
  if length(trim(coalesce(_service_name,'')))<2 then raise exception 'Service name is required'; end if;
  if target_department='' then raise exception 'Department is required'; end if;
  if coalesce(_amount,0)<0 then raise exception 'Service amount cannot be negative'; end if;
  insert into public.service_tariffs(service_code,service_name,department,unit,amount,active,currency)
  values(upper(trim(_service_code)),trim(_service_name),target_department,coalesce(nullif(trim(_unit),''),'unit'),coalesce(_amount,0),true,upper(coalesce(nullif(trim(_currency),''),'GHS'))) returning * into r;
  perform public.record_system_audit('service_catalogue_created','billing','service_tariffs',r.id,'info',jsonb_build_object('service_code',r.service_code,'service_name',r.service_name,'department',r.department,'actor_id',uid));
  return r;
end; $$;
revoke all on function public.create_service_catalogue_item(text,text,text,text,numeric,text) from public,anon;
grant execute on function public.create_service_catalogue_item(text,text,text,text,numeric,text) to authenticated;

create or replace function public.create_lab_test_catalogue_item(_test_code text,_test_name text,_category text,_specimen_type text,_unit text,_reference_low numeric,_reference_high numeric,_reference_text text,_default_charge numeric,_turnaround_minutes integer)
returns public.lab_test_catalogue language plpgsql security definer set search_path=public as $$
declare r public.lab_test_catalogue; uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not public.current_user_has_catalogue_create_permission('create_items') and not public.current_user_has_catalogue_create_permission('create_services') then raise exception 'Create items or services privilege required'; end if;
  if length(trim(coalesce(_test_code,'')))<2 then raise exception 'Test code is required'; end if;
  if length(trim(coalesce(_test_name,'')))<2 then raise exception 'Test name is required'; end if;
  if coalesce(_default_charge,0)<0 then raise exception 'Charge cannot be negative'; end if;
  if coalesce(_turnaround_minutes,0)<0 then raise exception 'Turnaround time cannot be negative'; end if;
  insert into public.lab_test_catalogue(test_code,test_name,category,specimen_type,unit,reference_low,reference_high,reference_text,default_charge,turnaround_minutes,active)
  values(upper(trim(_test_code)),trim(_test_name),nullif(trim(coalesce(_category,'')),''),nullif(trim(coalesce(_specimen_type,'')),''),nullif(trim(coalesce(_unit,'')),''),_reference_low,_reference_high,nullif(trim(coalesce(_reference_text,'')),''),coalesce(_default_charge,0),coalesce(_turnaround_minutes,0),true) returning * into r;
  perform public.record_system_audit('lab_test_catalogue_created','laboratory','lab_test_catalogue',r.id,'info',jsonb_build_object('test_code',r.test_code,'test_name',r.test_name,'actor_id',uid));
  return r;
end; $$;
revoke all on function public.create_lab_test_catalogue_item(text,text,text,text,text,numeric,numeric,text,numeric,integer) from public,anon;
grant execute on function public.create_lab_test_catalogue_item(text,text,text,text,text,numeric,numeric,text,numeric,integer) to authenticated;

create or replace function public.create_pharmacy_inventory_item(_drug_name text,_brand_name text,_generic_name text,_strength text,_form text,_supplier text,_batch_number text,_expiry_date date,_stock_quantity integer,_reorder_level integer,_unit_price numeric)
returns public.pharmacy_inventory language plpgsql security definer set search_path=public as $$
declare r public.pharmacy_inventory; uid uuid:=auth.uid();
begin
  if uid is null or not (public.has_role(uid,'admin') or public.has_role(uid,'it_admin') or public.has_role(uid,'pharmacist') or public.current_user_has_catalogue_create_permission('create_items')) then raise exception 'Create pharmacy item privilege required'; end if;
  if length(trim(coalesce(_drug_name,'')))<2 then raise exception 'Drug name is required'; end if;
  if coalesce(_stock_quantity,0)<0 or coalesce(_reorder_level,0)<0 or coalesce(_unit_price,0)<0 then raise exception 'Inventory values cannot be negative'; end if;
  if _expiry_date is not null and _expiry_date < current_date then raise exception 'Expiry date cannot be in the past'; end if;
  if coalesce(_unit_price,0)=0 and coalesce(_stock_quantity,0)>0 then raise exception 'Unit price is required for stocked inventory'; end if;
  insert into public.pharmacy_inventory(drug_name,brand_name,generic_name,strength,form,supplier,batch_number,expiry_date,stock_quantity,reorder_level,unit_price)
  values(trim(_drug_name),nullif(trim(_brand_name),''),nullif(trim(_generic_name),''),nullif(trim(_strength),''),nullif(trim(_form),''),nullif(trim(_supplier),''),nullif(trim(_batch_number),''),_expiry_date,coalesce(_stock_quantity,0),coalesce(_reorder_level,0),coalesce(_unit_price,0)) returning * into r;
  perform public.record_system_audit('pharmacy_inventory_created','pharmacy','pharmacy_inventory',r.id,'info',jsonb_build_object('drug_name',r.drug_name,'stock_quantity',r.stock_quantity,'actor_id',uid));
  return r;
end; $$;
revoke all on function public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric) from public,anon;
grant execute on function public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric) to authenticated;

insert into public.permissions(permission_key,description,is_active) values ('create_services','Create billable services in the user''s department',true),('create_items','Create departmental catalogue items',true)
on conflict(permission_key) do update set description=excluded.description,is_active=true;
insert into public.role_permissions(role,permission_key) values ('pharmacist','create_items'),('lab_technician','create_items'),('lab_technician','create_services'),('accountant','create_services') on conflict do nothing;
notify pgrst,'reload schema';