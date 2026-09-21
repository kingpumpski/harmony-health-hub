DROP POLICY IF EXISTS "staff read service order events" ON public.service_order_events;
CREATE POLICY "staff read service order events" ON public.service_order_events FOR SELECT TO authenticated
USING (
  public.has_role((SELECT auth.uid()),'admin'::public.app_role)
  OR public.has_role((SELECT auth.uid()),'accountant'::public.app_role)
  OR public.is_clinical_staff((SELECT auth.uid()))
);