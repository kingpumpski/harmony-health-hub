create or replace function private.current_user_can_select_facility_record(_target_facility_id uuid,_scope_code text default null) returns boolean language sql stable security definer set search_path='' as $$
select public.current_user_has_role('system_superuser') or (_target_facility_id is not null and _target_facility_id=public.current_user_facility_id()) or (_scope_code is not null and private.current_user_has_facility_data_scope(_target_facility_id,_scope_code));
$$;
revoke all on function private.current_user_can_select_facility_record(uuid,text) from public;
grant usage on schema private to authenticated;
grant execute on function private.current_user_can_select_facility_record(uuid,text) to authenticated;

do $$
declare r record; v_scope text; v_excluded text[]:=array['facility_memberships','user_active_facilities','facility_notification_config','facility_notification_provider_connections','facility_report_config','notification_inbound_emails','notification_provider_credentials','notification_queue','scheduled_notifications','report_generation_runs','report_submissions'];
begin
 for r in select c.table_name from information_schema.columns c join information_schema.tables t on t.table_schema=c.table_schema and t.table_name=c.table_name where c.table_schema='public' and c.column_name='facility_id' and t.table_type='BASE TABLE' and c.table_name<>all(v_excluded) loop
  v_scope:=case r.table_name when 'patients' then 'patient_read' when 'lab_orders' then 'lab_read' when 'lab_results' then 'lab_read' when 'outside_lab_documents' then 'lab_read' when 'imaging_orders' then 'imaging_read' when 'prescriptions' then 'medication_read' when 'medication_administrations' then 'medication_read' when 'pharmacy_dispensing_plans' then 'medication_read' when 'patient_documents' then 'document_read' when 'billing_overrides' then 'billing_read' when 'insurance_cases' then 'billing_read' when 'insurance_claims' then 'billing_read' when 'invoice_items' then 'billing_read' when 'invoices' then 'billing_read' when 'patient_account_credits' then 'billing_read' when 'payments' then 'billing_read' when 'pharmacy_pos_sales' then 'billing_read' when 'facility_diagnosis_standards' then null else 'clinical_read' end;
  execute format('alter table public.%I enable row level security',r.table_name);
  execute format('drop policy if exists facility_identity_select_guard on public.%I',r.table_name);
  if v_scope is null then
   execute format('create policy facility_identity_select_guard on public.%I as restrictive for select to authenticated using (private.current_user_can_select_facility_record(facility_id,null))',r.table_name);
  else
   execute format('create policy facility_identity_select_guard on public.%I as restrictive for select to authenticated using ('||case when r.table_name='patients' then '(user_id=(select auth.uid())) or ' else '' end||'private.current_user_can_select_facility_record(facility_id,%L))',r.table_name,v_scope);
  end if;
 end loop;
end $$;
drop policy if exists facility_scope_preserves_assigned_patients on public.patients;
drop policy if exists facility_scope_preserves_assigned_clinical_rows on public.encounters;
drop policy if exists facility_scope_preserves_assigned_diagnoses on public.diagnoses;
comment on function private.current_user_can_select_facility_record(uuid,text) is 'Central read boundary for facility-owned records. Same-facility access is automatic; cross-facility access requires a matching active bilateral agreement and scope; System Superuser is platform-wide.';
