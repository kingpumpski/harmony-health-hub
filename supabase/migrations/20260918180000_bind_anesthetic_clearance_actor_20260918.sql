-- Bind anaesthetic clearance attribution to the authenticated clinician.
-- Preserve the strict clinical-role boundary while preventing client spoofing of cleared_by.
drop policy if exists aa_staff_insert on public.anesthetic_assessments;
create policy aa_staff_insert on public.anesthetic_assessments for insert to authenticated
with check (
  (cleared_by is null or cleared_by = (select auth.uid()))
  and (
    has_role((select auth.uid()),'admin'::app_role)
    or has_role((select auth.uid()),'practitioner'::app_role)
    or has_role((select auth.uid()),'nurse'::app_role)
    or has_role((select auth.uid()),'midwife'::app_role)
    or has_role((select auth.uid()),'specialist_nurse'::app_role)
  )
);

drop policy if exists aa_staff_update on public.anesthetic_assessments;
create policy aa_staff_update on public.anesthetic_assessments for update to authenticated
using (
  has_role((select auth.uid()),'admin'::app_role)
  or has_role((select auth.uid()),'practitioner'::app_role)
  or has_role((select auth.uid()),'nurse'::app_role)
  or has_role((select auth.uid()),'midwife'::app_role)
  or has_role((select auth.uid()),'specialist_nurse'::app_role)
)
with check (
  (cleared_by is null or cleared_by = (select auth.uid()))
  and (
    has_role((select auth.uid()),'admin'::app_role)
    or has_role((select auth.uid()),'practitioner'::app_role)
    or has_role((select auth.uid()),'nurse'::app_role)
    or has_role((select auth.uid()),'midwife'::app_role)
    or has_role((select auth.uid()),'specialist_nurse'::app_role)
  )
);