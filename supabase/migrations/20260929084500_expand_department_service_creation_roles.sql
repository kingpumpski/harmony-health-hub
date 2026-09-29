BEGIN;
INSERT INTO public.role_permissions(role,permission_key)
VALUES
  ('pharmacist','create_services'),
  ('radiologist','create_services'),
  ('radiology_technician','create_services')
ON CONFLICT DO NOTHING;
NOTIFY pgrst,'reload schema';
COMMIT;