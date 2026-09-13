-- Security reconciliation: remove anonymous RPC execution, close the
-- user_roles RLS gap, and pin helper-function search paths.
-- This preserves authenticated application RPC access.

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;

ALTER FUNCTION public.get_bmi_category(numeric) SET search_path = public;
ALTER FUNCTION public.calculate_triage_bmi() SET search_path = public;

DROP POLICY IF EXISTS "user_roles_select_own" ON public.user_roles;
CREATE POLICY "user_roles_select_own"
  ON public.user_roles
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

NOTIFY pgrst, 'reload schema';
