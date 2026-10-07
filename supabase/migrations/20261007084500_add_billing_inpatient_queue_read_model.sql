create or replace function public.get_active_inpatient_billing_queue(_limit integer default 200)
returns table(admission_id uuid,patient_id uuid,admitted_at timestamptz,discharged_at timestamptz,ward text,bed text,status text)
language plpgsql stable security definer set search_path=''
as $function$
declare uid uuid:=auth.uid(); v_role text; v_facility uuid; v_limit integer:=greatest(1,least(coalesce(_limit,200),500));
begin
 if uid is null then raise exception 'Authentication required'; end if;
 select case when public.has_role(uid,'system_superuser'::public.app_role) then 'system_superuser' when public.has_role(uid,'admin'::public.app_role) then 'admin' when public.has_role(uid,'it_admin'::public.app_role) then 'it_admin' when public.has_role(uid,'accountant'::public.app_role) then 'accountant' when public.has_role(uid,'front_desk'::public.app_role) then 'front_desk' else null end into v_role;
 if v_role is null then raise exception 'Inpatient billing access is not permitted'; end if;
 v_facility:=public.current_user_facility_id();
 if v_role not in ('admin','it_admin','system_superuser') and v_facility is null then raise exception 'An active facility is required for inpatient billing'; end if;
 return query select a.id,a.patient_id,a.admitted_at,a.discharged_at,a.ward,a.bed,a.status from public.admissions a join public.patients p on p.id=a.patient_id where a.status='admitted' and a.discharged_at is null and p.status<>'inactive' and (v_role='system_superuser' or (v_role in ('admin','it_admin') and v_facility is null) or coalesce(a.facility_id,p.facility_id)=v_facility) order by a.admitted_at desc limit v_limit;
end;$function$;
revoke execute on function public.get_active_inpatient_billing_queue(integer) from public,anon;
grant execute on function public.get_active_inpatient_billing_queue(integer) to authenticated;