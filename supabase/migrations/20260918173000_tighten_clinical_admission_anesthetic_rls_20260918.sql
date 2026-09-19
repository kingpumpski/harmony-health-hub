drop policy if exists aa_staff_insert on public.anesthetic_assessments;
drop policy if exists aa_staff_update on public.anesthetic_assessments;
drop policy if exists aa_staff_delete on public.anesthetic_assessments;
create policy aa_staff_insert on public.anesthetic_assessments for insert to authenticated
with check (has_role((select auth.uid()),'admin'::app_role) or has_role((select auth.uid()),'practitioner'::app_role) or has_role((select auth.uid()),'nurse'::app_role) or has_role((select auth.uid()),'midwife'::app_role) or has_role((select auth.uid()),'specialist_nurse'::app_role));
create policy aa_staff_update on public.anesthetic_assessments for update to authenticated
using (has_role((select auth.uid()),'admin'::app_role) or has_role((select auth.uid()),'practitioner'::app_role) or has_role((select auth.uid()),'nurse'::app_role) or has_role((select auth.uid()),'midwife'::app_role) or has_role((select auth.uid()),'specialist_nurse'::app_role))
with check (has_role((select auth.uid()),'admin'::app_role) or has_role((select auth.uid()),'practitioner'::app_role) or has_role((select auth.uid()),'nurse'::app_role) or has_role((select auth.uid()),'midwife'::app_role) or has_role((select auth.uid()),'specialist_nurse'::app_role));
create policy aa_staff_delete on public.anesthetic_assessments for delete to authenticated
using (has_role((select auth.uid()),'admin'::app_role) or has_role((select auth.uid()),'practitioner'::app_role) or has_role((select auth.uid()),'nurse'::app_role) or has_role((select auth.uid()),'midwife'::app_role) or has_role((select auth.uid()),'specialist_nurse'::app_role));

drop policy if exists "staff insert admissions" on public.admissions;
drop policy if exists "staff update admissions" on public.admissions;
drop policy if exists "staff delete admissions" on public.admissions;
create policy "staff insert admissions" on public.admissions for insert to authenticated
with check (has_role((select auth.uid()),'admin'::app_role) or has_role((select auth.uid()),'practitioner'::app_role) or has_role((select auth.uid()),'nurse'::app_role) or has_role((select auth.uid()),'midwife'::app_role) or has_role((select auth.uid()),'specialist_nurse'::app_role));
create policy "staff update admissions" on public.admissions for update to authenticated
using (has_role((select auth.uid()),'admin'::app_role) or has_role((select auth.uid()),'practitioner'::app_role) or has_role((select auth.uid()),'nurse'::app_role) or has_role((select auth.uid()),'midwife'::app_role) or has_role((select auth.uid()),'specialist_nurse'::app_role))
with check (has_role((select auth.uid()),'admin'::app_role) or has_role((select auth.uid()),'practitioner'::app_role) or has_role((select auth.uid()),'nurse'::app_role) or has_role((select auth.uid()),'midwife'::app_role) or has_role((select auth.uid()),'specialist_nurse'::app_role));
create policy "staff delete admissions" on public.admissions for delete to authenticated
using (has_role((select auth.uid()),'admin'::app_role) or has_role((select auth.uid()),'practitioner'::app_role) or has_role((select auth.uid()),'nurse'::app_role) or has_role((select auth.uid()),'midwife'::app_role) or has_role((select auth.uid()),'specialist_nurse'::app_role));