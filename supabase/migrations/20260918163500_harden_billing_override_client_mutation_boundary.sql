-- Keep billing overrides server-authoritative.
-- Clients may read authorized overrides, but may not create/change/delete them directly.
DROP POLICY IF EXISTS bo_clinical_all ON public.billing_overrides;
DROP POLICY IF EXISTS billing_overrides_staff_read ON public.billing_overrides;
CREATE POLICY billing_overrides_staff_read
ON public.billing_overrides FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(),'admin')
  OR public.has_role(auth.uid(),'accountant')
  OR public.is_clinical_staff(auth.uid())
);
REVOKE ALL ON public.billing_overrides FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.billing_overrides FROM authenticated;
NOTIFY pgrst,'reload schema';
