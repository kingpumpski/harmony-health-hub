create schema if not exists private;

create table if not exists public.facility_data_sharing_agreements (
  id uuid primary key default gen_random_uuid(),
  facility_a_id uuid not null references public.healthcare_facilities(id) on delete restrict,
  facility_b_id uuid not null references public.healthcare_facilities(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','active','suspended','revoked','expired')),
  purpose text not null,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  facility_a_approved_by uuid references auth.users(id),
  facility_a_approved_at timestamptz,
  facility_b_approved_by uuid references auth.users(id),
  facility_b_approved_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_by uuid references auth.users(id),
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  constraint facility_data_sharing_agreements_distinct_facilities check (facility_a_id <> facility_b_id),
  constraint facility_data_sharing_agreements_dates check (effective_to is null or effective_to > effective_from)
);
create unique index if not exists facility_data_sharing_agreements_pair_active_idx on public.facility_data_sharing_agreements (least(facility_a_id,facility_b_id), greatest(facility_a_id,facility_b_id)) where status in ('pending','active','suspended');
create index if not exists facility_data_sharing_agreements_a_idx on public.facility_data_sharing_agreements(facility_a_id,status);
create index if not exists facility_data_sharing_agreements_b_idx on public.facility_data_sharing_agreements(facility_b_id,status);

create table if not exists public.facility_data_sharing_agreement_scopes (
  agreement_id uuid not null references public.facility_data_sharing_agreements(id) on delete cascade,
  scope_code text not null,
  created_at timestamptz not null default now(),
  primary key (agreement_id,scope_code)
);
create index if not exists facility_data_sharing_agreement_scopes_scope_idx on public.facility_data_sharing_agreement_scopes(scope_code,agreement_id);

alter table public.facility_data_sharing_agreements enable row level security;
alter table public.facility_data_sharing_agreement_scopes enable row level security;
revoke all on table public.facility_data_sharing_agreements from anon, authenticated;
revoke all on table public.facility_data_sharing_agreement_scopes from anon, authenticated;
grant select on public.facility_data_sharing_agreements to authenticated;
grant select on public.facility_data_sharing_agreement_scopes to authenticated;

drop policy if exists facility_data_sharing_agreements_read on public.facility_data_sharing_agreements;
create policy facility_data_sharing_agreements_read on public.facility_data_sharing_agreements for select to authenticated using (public.current_user_has_role('system_superuser') or facility_a_id=public.current_user_facility_id() or facility_b_id=public.current_user_facility_id());
drop policy if exists facility_data_sharing_agreement_scopes_read on public.facility_data_sharing_agreement_scopes;
create policy facility_data_sharing_agreement_scopes_read on public.facility_data_sharing_agreement_scopes for select to authenticated using (public.current_user_has_role('system_superuser') or exists(select 1 from public.facility_data_sharing_agreements a where a.id=agreement_id and (a.facility_a_id=public.current_user_facility_id() or a.facility_b_id=public.current_user_facility_id())));

create or replace function private.current_user_has_facility_data_scope(_target_facility_id uuid,_scope_code text) returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and _target_facility_id is not null and (
 public.current_user_has_role('system_superuser')
 or _target_facility_id=public.current_user_facility_id()
 or exists(select 1 from public.facility_data_sharing_agreements a join public.facility_data_sharing_agreement_scopes s on s.agreement_id=a.id where a.status='active' and now()>=a.effective_from and (a.effective_to is null or now()<a.effective_to) and s.scope_code=_scope_code and ((a.facility_a_id=public.current_user_facility_id() and a.facility_b_id=_target_facility_id) or (a.facility_b_id=public.current_user_facility_id() and a.facility_a_id=_target_facility_id)) and a.facility_a_approved_by is not null and a.facility_b_approved_by is not null)
); $$;
revoke all on function private.current_user_has_facility_data_scope(uuid,text) from public;
grant usage on schema private to authenticated;
grant execute on function private.current_user_has_facility_data_scope(uuid,text) to authenticated;

create or replace function public.has_facility_access(_user_id uuid,_facility_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
select exists(select 1 from public.user_roles ur where ur.user_id=_user_id and ur.role='system_superuser'::public.app_role)
or exists(select 1 from public.user_active_facilities uaf join public.facility_memberships fm on fm.user_id=uaf.user_id and fm.facility_id=uaf.facility_id and fm.is_active=true join public.healthcare_facilities hf on hf.id=uaf.facility_id and hf.is_active=true where uaf.user_id=_user_id and uaf.facility_id=_facility_id)
or ((select count(*) from public.facility_memberships fm where fm.user_id=_user_id and fm.is_active=true)=1 and exists(select 1 from public.facility_memberships fm join public.healthcare_facilities hf on hf.id=fm.facility_id and hf.is_active=true where fm.user_id=_user_id and fm.facility_id=_facility_id and fm.is_active=true));
$$;

create or replace function public.current_user_has_facility_access(_facility_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
select public.has_facility_access(auth.uid(),_facility_id) or (auth.uid() is not null and private.current_user_has_facility_data_scope(_facility_id,'patient_read'));
$$;

revoke insert,update,delete on table public.user_active_facilities from authenticated;
drop policy if exists memberships_read on public.facility_memberships;
create policy memberships_read on public.facility_memberships for select to authenticated using (user_id=(select auth.uid()) or public.current_user_has_role('system_superuser') or (public.current_user_has_role('admin') and facility_id=public.current_user_facility_id()));

create or replace function public.set_user_facility_context(_user_id uuid,_facility_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or not public.current_user_has_role('system_superuser') then raise exception 'System Superuser access required'; end if;
 if not exists(select 1 from public.facility_memberships fm where fm.user_id=_user_id and fm.facility_id=_facility_id and fm.is_active=true) then raise exception 'User is not an active member of the target facility'; end if;
 insert into public.user_active_facilities(user_id,facility_id,updated_at) values(_user_id,_facility_id,now()) on conflict(user_id) do update set facility_id=excluded.facility_id,updated_at=now();
end; $$;
revoke all on function public.set_user_facility_context(uuid,uuid) from public;
grant execute on function public.set_user_facility_context(uuid,uuid) to authenticated;

create or replace function public.create_facility_data_sharing_agreement(_facility_a_id uuid,_facility_b_id uuid,_purpose text,_effective_from timestamptz,_effective_to timestamptz,_scopes text[]) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_scope text;
begin
 if auth.uid() is null or not public.current_user_has_role('system_superuser') then raise exception 'System Superuser access required'; end if;
 if _facility_a_id=_facility_b_id then raise exception 'Facilities must be different'; end if;
 if coalesce(trim(_purpose),'')='' then raise exception 'Purpose is required'; end if;
 if coalesce(array_length(_scopes,1),0)=0 then raise exception 'At least one data-sharing scope is required'; end if;
 if not exists(select 1 from public.healthcare_facilities where id=_facility_a_id and is_active) or not exists(select 1 from public.healthcare_facilities where id=_facility_b_id and is_active) then raise exception 'Both facilities must be active'; end if;
 insert into public.facility_data_sharing_agreements(facility_a_id,facility_b_id,purpose,effective_from,effective_to,created_by) values(_facility_a_id,_facility_b_id,_purpose,coalesce(_effective_from,now()),_effective_to,auth.uid()) returning id into v_id;
 foreach v_scope in array _scopes loop
  if v_scope not in ('patient_read','clinical_read','encounter_read','diagnosis_read','lab_read','imaging_read','medication_read','billing_read','document_read','care_coordination') then raise exception 'Unsupported data-sharing scope: %',v_scope; end if;
  insert into public.facility_data_sharing_agreement_scopes(agreement_id,scope_code) values(v_id,v_scope);
 end loop;
 insert into public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata) values(auth.uid(),'facility_data_sharing_agreement_created','administration','facility_data_sharing_agreement',v_id,'info',jsonb_build_object('facility_a_id',_facility_a_id,'facility_b_id',_facility_b_id,'purpose',_purpose,'scopes',_scopes));
 return v_id;
end; $$;
revoke all on function public.create_facility_data_sharing_agreement(uuid,uuid,text,timestamptz,timestamptz,text[]) from public;
grant execute on function public.create_facility_data_sharing_agreement(uuid,uuid,text,timestamptz,timestamptz,text[]) to authenticated;

create or replace function public.approve_facility_data_sharing_agreement(_agreement_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v_a uuid;v_b uuid;v_facility uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select facility_a_id,facility_b_id into v_a,v_b from public.facility_data_sharing_agreements where id=_agreement_id for update;
 if v_a is null then raise exception 'Agreement not found'; end if;
 if public.current_user_has_role('system_superuser') then
  update public.facility_data_sharing_agreements set facility_a_approved_by=coalesce(facility_a_approved_by,auth.uid()),facility_a_approved_at=coalesce(facility_a_approved_at,now()),facility_b_approved_by=coalesce(facility_b_approved_by,auth.uid()),facility_b_approved_at=coalesce(facility_b_approved_at,now()),status=case when status in ('revoked','expired') then status else 'active' end,updated_at=now() where id=_agreement_id; return;
 end if;
 v_facility:=public.current_user_facility_id();
 if not(public.current_user_has_role('admin') or public.current_user_has_role('it_admin')) then raise exception 'Facility administrator access required'; end if;
 if v_facility is null or v_facility not in(v_a,v_b) then raise exception 'Agreement is outside your facility'; end if;
 if v_facility=v_a then update public.facility_data_sharing_agreements set facility_a_approved_by=auth.uid(),facility_a_approved_at=now(),updated_at=now() where id=_agreement_id; else update public.facility_data_sharing_agreements set facility_b_approved_by=auth.uid(),facility_b_approved_at=now(),updated_at=now() where id=_agreement_id; end if;
 update public.facility_data_sharing_agreements set status='active',updated_at=now() where id=_agreement_id and facility_a_approved_by is not null and facility_b_approved_by is not null and status not in('revoked','expired');
 insert into public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata) values(auth.uid(),'facility_data_sharing_agreement_approved','administration','facility_data_sharing_agreement',_agreement_id,'info',jsonb_build_object('facility_id',v_facility));
end; $$;
revoke all on function public.approve_facility_data_sharing_agreement(uuid) from public;
grant execute on function public.approve_facility_data_sharing_agreement(uuid) to authenticated;

create or replace function public.revoke_facility_data_sharing_agreement(_agreement_id uuid,_reason text) returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or not public.current_user_has_role('system_superuser') then raise exception 'System Superuser access required'; end if;
 if coalesce(trim(_reason),'')='' then raise exception 'Revocation reason is required'; end if;
 update public.facility_data_sharing_agreements set status='revoked',revoked_by=auth.uid(),revoked_at=now(),updated_at=now(),metadata=metadata||jsonb_build_object('revocation_reason',_reason) where id=_agreement_id;
 if not found then raise exception 'Agreement not found'; end if;
 insert into public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata) values(auth.uid(),'facility_data_sharing_agreement_revoked','administration','facility_data_sharing_agreement',_agreement_id,'warning',jsonb_build_object('reason',_reason));
end; $$;
revoke all on function public.revoke_facility_data_sharing_agreement(uuid,text) from public;
grant execute on function public.revoke_facility_data_sharing_agreement(uuid,text) to authenticated;
comment on table public.facility_data_sharing_agreements is 'Explicit bilateral, time-bounded facility-to-facility data sharing agreements. Clinical record isolation remains deny-by-default.';
comment on table public.facility_data_sharing_agreement_scopes is 'Data access scopes attached to an explicit facility sharing agreement.';
