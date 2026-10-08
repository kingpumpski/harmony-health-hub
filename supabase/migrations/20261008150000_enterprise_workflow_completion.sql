-- Enterprise workflow completion and specialist-role authorization.
-- One canonical identity/RBAC model; specialization is facility-scoped.

create or replace function public.hms_user_can(
  _facility_id uuid,_module_id text,_action text,_user_id uuid default auth.uid()
)
returns boolean
language sql stable security definer
set search_path=public
as $$
  select auth.uid() is not null
    and _user_id=auth.uid()
    and public.has_facility_access(_user_id,_facility_id)
    and public.hms_module_is_enabled(_facility_id,_module_id)
    and (
      public.has_role(_user_id,'admin'::public.app_role)
      or public.has_role(_user_id,'system_superuser'::public.app_role)
      or exists (
        select 1
        from public.hms_role_codes_for_user(_user_id) rc
        join public.hms_role_module_permissions p on p.role_code=rc.role_code
        join public.hms_module_catalog m on m.module_code=p.module_code or m.module_id=p.module_code
        where m.module_id=_module_id
          and case lower(_action)
            when 'read' then p.can_read
            when 'write' then p.can_write
            when 'approve' then p.can_approve
            when 'configure' then p.can_configure
            else false end
      )
      or exists (
        select 1
        from public.hms_user_role_assignments a
        join public.hms_role_module_permissions p on p.role_code=a.role_code
        join public.hms_module_catalog m on m.module_code=p.module_code or m.module_id=p.module_code
        where a.user_id=_user_id and a.facility_id=_facility_id and a.active=true
          and a.effective_from<=now() and (a.effective_to is null or a.effective_to>now())
          and m.module_id=_module_id
          and case lower(_action)
            when 'read' then p.can_read
            when 'write' then p.can_write
            when 'approve' then p.can_approve
            when 'configure' then p.can_configure
            else false end
      )
    );
$$;
revoke all on function public.hms_user_can(uuid,text,text,uuid) from public,anon;
grant execute on function public.hms_user_can(uuid,text,text,uuid) to authenticated;

create or replace function public.hms_assert_enterprise_access(
  _facility_id uuid,_module_id text,_action text default 'read'
)
returns void language plpgsql security invoker set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if not public.hms_user_can(_facility_id,_module_id,_action,auth.uid()) then
    raise exception 'HMS authorization denied for module % action %',_module_id,_action using errcode='42501';
  end if;
end;
$$;
revoke all on function public.hms_assert_enterprise_access(uuid,text,text) from public,anon;
grant execute on function public.hms_assert_enterprise_access(uuid,text,text) to authenticated;

create or replace function public.set_hms_specialist_role(
  _target_user_id uuid,_role_code text,_facility_id uuid,_department_code text default null
)
returns public.hms_user_role_assignments
language plpgsql security definer set search_path=public as $$
declare r public.hms_user_role_assignments;
begin
  if auth.uid() is null or not (
    public.has_role(auth.uid(),'admin'::public.app_role)
    or public.has_role(auth.uid(),'system_superuser'::public.app_role)
    or public.has_role(auth.uid(),'it_admin'::public.app_role)
  ) then raise exception 'Administrator authorization required' using errcode='42501'; end if;
  if not exists(select 1 from auth.users where id=_target_user_id) then raise exception 'Target user does not exist'; end if;
  if not exists(select 1 from public.hms_role_catalog where role_code=_role_code) then raise exception 'Unknown specialist role'; end if;
  if not public.has_facility_access(auth.uid(),_facility_id) and not public.has_role(auth.uid(),'system_superuser'::public.app_role) then
    raise exception 'Facility access denied' using errcode='42501';
  end if;
  insert into public.hms_user_role_assignments(user_id,role_code,facility_id,department_code,active,assigned_by)
  values(_target_user_id,_role_code,_facility_id,_department_code,true,auth.uid())
  on conflict(user_id,role_code,facility_id) do update set
    department_code=excluded.department_code,active=true,effective_from=now(),effective_to=null,assigned_by=auth.uid(),assigned_at=now()
  returning * into r;
  return r;
end;
$$;
revoke all on function public.set_hms_specialist_role(uuid,text,uuid,text) from public,anon;
grant execute on function public.set_hms_specialist_role(uuid,text,uuid,text) to authenticated;

create or replace function public.get_hms_my_specialist_roles()
returns table(role_code text,role_name text,facility_id uuid,facility_name text,department_code text,effective_from timestamptz,effective_to timestamptz)
language sql stable security definer set search_path=public as $$
  select a.role_code,r.role_name,a.facility_id,f.name,a.department_code,a.effective_from,a.effective_to
  from public.hms_user_role_assignments a
  join public.hms_role_catalog r on r.role_code=a.role_code
  join public.healthcare_facilities f on f.id=a.facility_id
  where a.user_id=auth.uid() and a.active=true
    and a.effective_from<=now() and (a.effective_to is null or a.effective_to>now())
    and public.has_facility_access(auth.uid(),a.facility_id)
  order by f.name,r.role_name;
$$;
revoke all on function public.get_hms_my_specialist_roles() from public,anon;
grant execute on function public.get_hms_my_specialist_roles() to authenticated;

-- A single governed read model powers the new enterprise workspaces without
-- exposing unrestricted table access. Returned data is intentionally scoped.
create or replace function public.hms_get_enterprise_workspace(_facility_id uuid,_module_id text)
returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v jsonb;
begin
  perform public.hms_assert_enterprise_access(_facility_id,_module_id,'read');
  case _module_id
    when 'hr-payroll' then
      select jsonb_build_object(
        'employees',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,employee_number,full_name,department_code,job_title,employment_status,hire_date from public.hms_hr_employees where facility_id=_facility_id order by created_at desc limit 100)x),'[]'::jsonb),
        'leave_requests',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select l.id,l.employee_id,l.leave_type,l.start_date,l.end_date,l.status,l.reason from public.hms_hr_leave_requests l join public.hms_hr_employees e on e.id=l.employee_id where e.facility_id=_facility_id order by l.created_at desc limit 100)x),'[]'::jsonb),
        'payroll_periods',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,period_start,period_end,status,approved_at from public.hms_payroll_periods where facility_id=_facility_id order by created_at desc limit 50)x),'[]'::jsonb)
      ) into v;
    when 'icu-critical-care' then
      select jsonb_build_object('stays',coalesce((select jsonb_agg(to_jsonb(x) order by x.admission_at desc) from (select id,patient_id,encounter_id,bed_reference,admission_at,discharge_at,acuity,status,diagnosis from public.hms_icu_stays where facility_id=_facility_id order by admission_at desc limit 100)x),'[]'::jsonb)) into v;
    when 'mental-health' then
      select jsonb_build_object('assessments',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,patient_id,encounter_id,assessor_id,risk_level,status,assessment,care_plan,created_at from public.hms_mental_health_assessments where facility_id=_facility_id order by created_at desc limit 100)x),'[]'::jsonb)) into v;
    when 'social-work' then
      select jsonb_build_object('cases',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,patient_id,encounter_id,assigned_to,case_type,safeguarding_level,status,assessment,interventions,created_at from public.hms_social_work_cases where facility_id=_facility_id order by created_at desc limit 100)x),'[]'::jsonb)) into v;
    when 'quality-compliance' then
      select jsonb_build_object('incidents',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,incident_code,category,severity,patient_id,status,description,reported_by,owner_id,occurred_at,created_at from public.hms_quality_incidents where facility_id=_facility_id order by created_at desc limit 100)x),'[]'::jsonb)) into v;
    when 'infection-control' then
      select jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,patient_id,event_type,organism,location,risk_level,status,reported_by,event_at,actions,created_at from public.hms_ipc_events where facility_id=_facility_id order by created_at desc limit 100)x),'[]'::jsonb)) into v;
    when 'mortuary' then
      select jsonb_build_object('cases',coalesce((select jsonb_agg(to_jsonb(x) order by x.received_at desc) from (select id,case_number,patient_id,received_at,storage_location,custody_status,release_to,released_at,identity_verification from public.hms_mortuary_cases where facility_id=_facility_id order by received_at desc limit 100)x),'[]'::jsonb)) into v;
    when 'ambulance' then
      select jsonb_build_object('trips',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,patient_id,ambulance_reference,dispatched_at,departed_at,arrived_at,returned_at,pickup_location,destination,crew,status,clinical_handover,created_at from public.hms_ambulance_trips where facility_id=_facility_id order by created_at desc limit 100)x),'[]'::jsonb)) into v;
    when 'research-portal' then
      select jsonb_build_object('projects',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,project_code,title,protocol_version,ethics_reference,status,principal_investigator,data_purpose,de_identified,retention_until,created_at from public.hms_research_projects where facility_id=_facility_id order by created_at desc limit 100)x),'[]'::jsonb)) into v;
    when 'external-audit' then
      select jsonb_build_object('engagements',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,auditor_user_id,audit_type,scope,status,starts_on,ends_on,evidence_request,created_at from public.hms_audit_engagements where facility_id=_facility_id order by created_at desc limit 100)x),'[]'::jsonb)) into v;
    when 'genomics' then
      select jsonb_build_object('orders',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,patient_id,encounter_id,ordered_by,test_code,specimen_reference,consent_reference,status,result_summary,provenance,created_at from public.hms_genomics_orders where facility_id=_facility_id order by created_at desc limit 100)x),'[]'::jsonb)) into v;
    else
      raise exception 'Unsupported enterprise workspace module';
  end case;
  return coalesce(v,'{}'::jsonb);
end;
$$;
revoke all on function public.hms_get_enterprise_workspace(uuid,text) from public,anon;
grant execute on function public.hms_get_enterprise_workspace(uuid,text) to authenticated;

-- Generic, schema-safe command boundary for the primary records in each new module.
create or replace function public.hms_create_enterprise_record(
  _facility_id uuid,_module_id text,_payload jsonb
)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
  perform public.hms_assert_enterprise_access(_facility_id,_module_id,'write');
  if _payload is null then raise exception 'Record payload is required'; end if;
  case _module_id
    when 'hr-payroll' then
      insert into public.hms_hr_employees(facility_id,employee_number,full_name,department_code,job_title,employment_status,hire_date,credentials,created_by)
      values(_facility_id,trim(_payload->>'employee_number'),trim(_payload->>'full_name'),nullif(trim(_payload->>'department_code'),''),nullif(trim(_payload->>'job_title'),''),coalesce(nullif(trim(_payload->>'employment_status'),''),'active'),nullif(_payload->>'hire_date','')::date,coalesce(_payload->'credentials','{}'::jsonb),auth.uid())
      returning to_jsonb(hms_hr_employees.*) into r;
    when 'icu-critical-care' then
      insert into public.hms_icu_stays(facility_id,patient_id,encounter_id,bed_reference,acuity,status,diagnosis,created_by)
      values(_facility_id,(_payload->>'patient_id')::uuid,nullif(_payload->>'encounter_id','')::uuid,nullif(trim(_payload->>'bed_reference'),''),coalesce(nullif(_payload->>'acuity',''),'high'),coalesce(nullif(_payload->>'status',''),'active'),coalesce(_payload->'diagnosis','{}'::jsonb),auth.uid())
      returning to_jsonb(hms_icu_stays.*) into r;
    when 'mental-health' then
      insert into public.hms_mental_health_assessments(facility_id,patient_id,encounter_id,assessor_id,assessment,risk_level,care_plan,status)
      values(_facility_id,(_payload->>'patient_id')::uuid,nullif(_payload->>'encounter_id','')::uuid,auth.uid(),coalesce(_payload->'assessment','{}'::jsonb),coalesce(nullif(_payload->>'risk_level',''),'unknown'),coalesce(_payload->'care_plan','{}'::jsonb),coalesce(nullif(_payload->>'status',''),'draft'))
      returning to_jsonb(hms_mental_health_assessments.*) into r;
    when 'social-work' then
      insert into public.hms_social_work_cases(facility_id,patient_id,encounter_id,assigned_to,case_type,assessment,interventions,safeguarding_level,status)
      values(_facility_id,(_payload->>'patient_id')::uuid,nullif(_payload->>'encounter_id','')::uuid,nullif(_payload->>'assigned_to','')::uuid,trim(_payload->>'case_type'),coalesce(_payload->'assessment','{}'::jsonb),coalesce(_payload->'interventions','{}'::jsonb),coalesce(nullif(_payload->>'safeguarding_level',''),'none'),coalesce(nullif(_payload->>'status',''),'open'))
      returning to_jsonb(hms_social_work_cases.*) into r;
    when 'quality-compliance' then
      insert into public.hms_quality_incidents(facility_id,incident_code,category,severity,patient_id,description,status,reported_by,owner_id,occurred_at)
      values(_facility_id,trim(_payload->>'incident_code'),trim(_payload->>'category'),coalesce(nullif(_payload->>'severity',''),'moderate'),nullif(_payload->>'patient_id','')::uuid,trim(_payload->>'description'),coalesce(nullif(_payload->>'status',''),'open'),auth.uid(),nullif(_payload->>'owner_id','')::uuid,nullif(_payload->>'occurred_at','')::timestamptz)
      returning to_jsonb(hms_quality_incidents.*) into r;
    when 'infection-control' then
      insert into public.hms_ipc_events(facility_id,patient_id,event_type,organism,location,risk_level,status,reported_by,event_at,actions)
      values(_facility_id,nullif(_payload->>'patient_id','')::uuid,trim(_payload->>'event_type'),nullif(trim(_payload->>'organism'),''),nullif(trim(_payload->>'location'),''),coalesce(nullif(_payload->>'risk_level',''),'moderate'),coalesce(nullif(_payload->>'status',''),'open'),auth.uid(),nullif(_payload->>'event_at','')::timestamptz,coalesce(_payload->'actions','{}'::jsonb))
      returning to_jsonb(hms_ipc_events.*) into r;
    when 'mortuary' then
      insert into public.hms_mortuary_cases(facility_id,patient_id,case_number,storage_location,custody_status,release_to,identity_verification,created_by)
      values(_facility_id,nullif(_payload->>'patient_id','')::uuid,trim(_payload->>'case_number'),nullif(trim(_payload->>'storage_location'),''),coalesce(nullif(_payload->>'custody_status',''),'received'),nullif(trim(_payload->>'release_to'),''),coalesce(_payload->'identity_verification','{}'::jsonb),auth.uid())
      returning to_jsonb(hms_mortuary_cases.*) into r;
    when 'ambulance' then
      insert into public.hms_ambulance_trips(facility_id,patient_id,ambulance_reference,pickup_location,destination,crew,status,clinical_handover,requested_by)
      values(_facility_id,nullif(_payload->>'patient_id','')::uuid,nullif(trim(_payload->>'ambulance_reference'),''),nullif(trim(_payload->>'pickup_location'),''),nullif(trim(_payload->>'destination'),''),coalesce(_payload->'crew','[]'::jsonb),coalesce(nullif(_payload->>'status',''),'requested'),coalesce(_payload->'clinical_handover','{}'::jsonb),auth.uid())
      returning to_jsonb(hms_ambulance_trips.*) into r;
    when 'research-portal' then
      insert into public.hms_research_projects(facility_id,project_code,title,protocol_version,ethics_reference,status,principal_investigator,data_purpose,de_identified,retention_until,created_by)
      values(_facility_id,trim(_payload->>'project_code'),trim(_payload->>'title'),nullif(trim(_payload->>'protocol_version'),''),nullif(trim(_payload->>'ethics_reference'),''),coalesce(nullif(_payload->>'status',''),'draft'),nullif(_payload->>'principal_investigator','')::uuid,trim(_payload->>'data_purpose'),coalesce((_payload->>'de_identified')::boolean,true),nullif(_payload->>'retention_until','')::date,auth.uid())
      returning to_jsonb(hms_research_projects.*) into r;
    when 'external-audit' then
      insert into public.hms_audit_engagements(facility_id,auditor_user_id,audit_type,scope,status,starts_on,ends_on,evidence_request,created_by)
      values(_facility_id,nullif(_payload->>'auditor_user_id','')::uuid,trim(_payload->>'audit_type'),coalesce(_payload->'scope','{}'::jsonb),coalesce(nullif(_payload->>'status',''),'planned'),nullif(_payload->>'starts_on','')::date,nullif(_payload->>'ends_on','')::date,coalesce(_payload->'evidence_request','{}'::jsonb),auth.uid())
      returning to_jsonb(hms_audit_engagements.*) into r;
    when 'genomics' then
      insert into public.hms_genomics_orders(facility_id,patient_id,encounter_id,ordered_by,test_code,specimen_reference,consent_reference,status,result_summary,provenance)
      values(_facility_id,(_payload->>'patient_id')::uuid,nullif(_payload->>'encounter_id','')::uuid,auth.uid(),trim(_payload->>'test_code'),nullif(trim(_payload->>'specimen_reference'),''),nullif(trim(_payload->>'consent_reference'),''),coalesce(nullif(_payload->>'status',''),'ordered'),coalesce(_payload->'result_summary','{}'::jsonb),coalesce(_payload->'provenance','{}'::jsonb))
      returning to_jsonb(hms_genomics_orders.*) into r;
    else
      raise exception 'Unsupported enterprise create module';
  end case;
  return r;
exception when others then
  raise exception '%',sqlerrm using errcode='P0001';
end;
$$;
revoke all on function public.hms_create_enterprise_record(uuid,text,jsonb) from public,anon;
grant execute on function public.hms_create_enterprise_record(uuid,text,jsonb) to authenticated;

comment on function public.hms_user_can(uuid,text,text,uuid) is 'Canonical facility-scoped authorization including specialist role assignments.';
comment on function public.hms_get_enterprise_workspace(uuid,text) is 'Scoped read model for newly operationalized enterprise modules.';
