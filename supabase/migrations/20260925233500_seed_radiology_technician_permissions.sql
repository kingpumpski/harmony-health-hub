-- Align the database-backed permission catalog with the production imaging role.
-- The role already exists in public.app_role; this migration only seeds its
-- navigation/workspace permissions and is idempotent.

INSERT INTO public.role_permissions (role, permission_key)
VALUES
  ('radiology_technician'::public.app_role, 'dashboard'),
  ('radiology_technician'::public.app_role, 'radiology'),
  ('radiology_technician'::public.app_role, 'department_queue'),
  ('radiology_technician'::public.app_role, 'patients'),
  ('radiology_technician'::public.app_role, 'notifications')
ON CONFLICT DO NOTHING;
