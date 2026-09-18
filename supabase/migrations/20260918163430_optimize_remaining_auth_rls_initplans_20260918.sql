-- Optimize auth helper evaluation in high-traffic RLS policies without changing authorization semantics.
DROP POLICY IF EXISTS billing_overrides_staff_read ON public.billing_overrides;
CREATE POLICY billing_overrides_staff_read ON public.billing_overrides FOR SELECT TO authenticated
USING ((SELECT public.has_role((SELECT auth.uid()),'admin')) OR (SELECT public.has_role((SELECT auth.uid()),'accountant')) OR (SELECT public.is_clinical_staff((SELECT auth.uid()))));
DROP POLICY IF EXISTS "admins manage migration batches" ON public.data_migration_batches;
CREATE POLICY "admins manage migration batches" ON public.data_migration_batches FOR ALL TO authenticated
USING ((SELECT public.has_role((SELECT auth.uid()),'admin'))) WITH CHECK ((SELECT public.has_role((SELECT auth.uid()),'admin')));
DROP POLICY IF EXISTS "admins manage migration rows" ON public.data_migration_rows;
CREATE POLICY "admins manage migration rows" ON public.data_migration_rows FOR ALL TO authenticated
USING ((SELECT public.has_role((SELECT auth.uid()),'admin'))) WITH CHECK ((SELECT public.has_role((SELECT auth.uid()),'admin')));
DROP POLICY IF EXISTS "admins manage patient audit" ON public.patient_audit_log;
CREATE POLICY "admins manage patient audit" ON public.patient_audit_log FOR ALL TO authenticated
USING ((SELECT public.has_role((SELECT auth.uid()),'admin'))) WITH CHECK ((SELECT public.has_role((SELECT auth.uid()),'admin')));
DROP POLICY IF EXISTS "staff read patient audit" ON public.patient_audit_log;
CREATE POLICY "staff read patient audit" ON public.patient_audit_log FOR SELECT TO authenticated
USING ((SELECT public.is_clinical_staff((SELECT auth.uid()))) OR (SELECT public.has_role((SELECT auth.uid()),'specialist_nurse')) OR (SELECT public.has_role((SELECT auth.uid()),'admin')));
DROP POLICY IF EXISTS "staff read visit authorizations" ON public.patient_visit_authorizations;
CREATE POLICY "staff read visit authorizations" ON public.patient_visit_authorizations FOR SELECT TO authenticated
USING ((SELECT public.has_role((SELECT auth.uid()),'admin')) OR (SELECT public.has_role((SELECT auth.uid()),'accountant')) OR (SELECT public.has_role((SELECT auth.uid()),'front_desk')) OR (SELECT public.is_clinical_staff((SELECT auth.uid()))) OR EXISTS (SELECT 1 FROM public.patients p WHERE p.id=patient_visit_authorizations.patient_id AND p.user_id=(SELECT auth.uid())));
DROP POLICY IF EXISTS service_orders_staff_read ON public.service_orders;
CREATE POLICY service_orders_staff_read ON public.service_orders FOR SELECT TO authenticated
USING ((SELECT public.has_role((SELECT auth.uid()),'admin')) OR (SELECT public.has_role((SELECT auth.uid()),'accountant')) OR (SELECT public.has_role((SELECT auth.uid()),'front_desk')) OR (SELECT public.is_clinical_staff((SELECT auth.uid()))));