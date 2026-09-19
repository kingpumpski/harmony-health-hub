-- Consolidate overlapping SELECT policies without changing mutation authority.
drop policy if exists "admins manage legacy records" on public.legacy_clinical_records;
drop policy if exists "clinical read legacy records" on public.legacy_clinical_records;
create policy "legacy records staff read" on public.legacy_clinical_records for select to authenticated
using (
  has_role((select auth.uid()),'admin'::app_role)
  or has_role((select auth.uid()),'practitioner'::app_role)
  or has_role((select auth.uid()),'nurse'::app_role)
  or has_role((select auth.uid()),'midwife'::app_role)
  or has_role((select auth.uid()),'specialist_nurse'::app_role)
);
create policy "legacy records admin insert" on public.legacy_clinical_records for insert to authenticated with check (has_role((select auth.uid()),'admin'::app_role));
create policy "legacy records admin update" on public.legacy_clinical_records for update to authenticated using (has_role((select auth.uid()),'admin'::app_role)) with check (has_role((select auth.uid()),'admin'::app_role));
create policy "legacy records admin delete" on public.legacy_clinical_records for delete to authenticated using (has_role((select auth.uid()),'admin'::app_role));

drop policy if exists "admins manage patient audit" on public.patient_audit_log;
drop policy if exists "staff read patient audit" on public.patient_audit_log;
create policy "staff read patient audit" on public.patient_audit_log for select to authenticated
using (
  is_clinical_staff((select auth.uid()))
  or has_role((select auth.uid()),'admin'::app_role)
);
create policy "admin insert patient audit" on public.patient_audit_log for insert to authenticated with check (has_role((select auth.uid()),'admin'::app_role));
create policy "admin update patient audit" on public.patient_audit_log for update to authenticated using (has_role((select auth.uid()),'admin'::app_role)) with check (has_role((select auth.uid()),'admin'::app_role));
create policy "admin delete patient audit" on public.patient_audit_log for delete to authenticated using (has_role((select auth.uid()),'admin'::app_role));

drop policy if exists "admins manage master data" on public.system_master_data;
create policy "admin insert master data" on public.system_master_data for insert to authenticated with check (has_role((select auth.uid()),'admin'::app_role));
create policy "admin update master data" on public.system_master_data for update to authenticated using (has_role((select auth.uid()),'admin'::app_role)) with check (has_role((select auth.uid()),'admin'::app_role));
create policy "admin delete master data" on public.system_master_data for delete to authenticated using (has_role((select auth.uid()),'admin'::app_role));