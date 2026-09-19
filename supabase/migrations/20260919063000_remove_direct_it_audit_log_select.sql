DROP POLICY IF EXISTS "system audit admin and it support read" ON public.system_audit_log;
CREATE POLICY "system audit admin read"
ON public.system_audit_log
FOR SELECT TO authenticated
USING (public.has_role((SELECT auth.uid()), 'admin'::public.app_role));
NOTIFY pgrst, 'reload schema';