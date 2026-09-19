-- Configure scoped IT Admin support permissions after the enum value exists.
INSERT INTO public.permissions(permission_key, description, is_active)
VALUES ('it_support','IT support domain: system diagnostics, audit visibility and offline synchronization support',TRUE)
ON CONFLICT(permission_key) DO UPDATE SET description=EXCLUDED.description, is_active=TRUE;

INSERT INTO public.role_permissions(role, permission_key)
VALUES
  ('it_admin','dashboard'),
  ('it_admin','it_support'),
  ('it_admin','notifications'),
  ('it_admin','offline_sync')
ON CONFLICT DO NOTHING;

DROP POLICY IF EXISTS "system audit admin read" ON public.system_audit_log;
CREATE POLICY "system audit admin and it support read"
ON public.system_audit_log
FOR SELECT TO authenticated
USING (
  public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
  OR public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role)
);
