BEGIN;

INSERT INTO public.permissions(permission_key, description, is_active)
VALUES (
  'system_settings',
  'System settings: facility configuration and notification delivery control plane',
  TRUE
)
ON CONFLICT (permission_key)
DO UPDATE SET
  description = EXCLUDED.description,
  is_active = TRUE,
  updated_at = now();

INSERT INTO public.role_permissions(role, permission_key)
VALUES
  ('admin'::public.app_role, 'system_settings'),
  ('it_admin'::public.app_role, 'system_settings')
ON CONFLICT DO NOTHING;

COMMIT;
