-- Functional-domain permission migration.
-- Keep legacy submodule keys for compatibility; add domain keys without deleting existing mappings.
INSERT INTO public.permissions(permission_key, description, is_active)
VALUES
  ('inpatient','Inpatient functional domain: admissions, movements, beds, handover and ward operations'),
  ('finance','Finance functional domain: billing, approvals, claims and reconciliation'),
  ('administration','Administration functional domain: users, permissions, settings, audit and system operations')
ON CONFLICT(permission_key) DO UPDATE SET description=EXCLUDED.description, is_active=TRUE;

INSERT INTO public.role_permissions(role, permission_key)
VALUES
  ('admin','inpatient'),('admin','finance'),('admin','administration'),
  ('practitioner','inpatient'),('practitioner','reports'),
  ('nurse','inpatient'),
  ('specialist_nurse','inpatient'),
  ('midwife','inpatient'),
  ('accountant','finance'),('accountant','reports'),
  ('front_desk','finance')
ON CONFLICT DO NOTHING;
