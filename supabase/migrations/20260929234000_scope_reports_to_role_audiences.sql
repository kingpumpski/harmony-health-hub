BEGIN;
UPDATE public.report_definitions SET audience_roles=ARRAY['admin','practitioner','front_desk'] WHERE report_code IN ('RPT-001','RPT-002');
UPDATE public.report_definitions SET audience_roles=ARRAY['admin','practitioner','nurse','specialist_nurse','midwife'] WHERE report_code IN ('RPT-003','RPT-004','RPT-005','RPT-006','RPT-007','RPT-008','RPT-010','RPT-011','RPT-019','RPT-020','RPT-022','RPT-030','RPT-031','RPT-034','RPT-035','RPT-036','RPT-037','RPT-038','RPT-039');
UPDATE public.report_definitions SET audience_roles=ARRAY['admin','midwife','practitioner','nurse'] WHERE report_code IN ('RPT-009','RPT-012','RPT-013','RPT-014','RPT-015','RPT-016','RPT-017','RPT-018','RPT-021','RPT-027');
UPDATE public.report_definitions SET audience_roles=ARRAY['admin','practitioner','nurse','specialist_nurse'] WHERE report_code IN ('RPT-023','RPT-024','RPT-025','RPT-026','RPT-028','RPT-029');
UPDATE public.report_definitions SET audience_roles=ARRAY['admin','lab_technician','practitioner','nurse','midwife'] WHERE report_code='RPT-041';
UPDATE public.report_definitions SET audience_roles=ARRAY['admin','it_admin','accountant'] WHERE report_code='RPT-040';
UPDATE public.report_definitions SET audience_roles=ARRAY['admin','practitioner','nurse','specialist_nurse','midwife','front_desk'] WHERE report_code IN ('RPT-032','RPT-033');
UPDATE public.report_definitions SET audience_roles=ARRAY['admin'] WHERE cardinality(audience_roles)=0;
DROP POLICY IF EXISTS report_definitions_read ON public.report_definitions;
CREATE POLICY report_definitions_read ON public.report_definitions FOR SELECT TO authenticated USING (
  is_active AND (
    public.has_role((select auth.uid()),'admin')
    OR public.has_role((select auth.uid()),'it_admin')
    OR cardinality(audience_roles)=0
    OR EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id=(select auth.uid()) AND ur.role::text = ANY(report_definitions.audience_roles)
    )
  )
);
COMMIT;