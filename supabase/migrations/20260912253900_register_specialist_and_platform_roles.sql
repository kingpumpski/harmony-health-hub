-- Register every role referenced by specialist and platform workflows before those
-- migrations create policies/functions that cast the values to app_role.
-- Keep enum additions isolated from references to the new values: PostgreSQL requires
-- the enum change to commit before later migrations can use those values.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'radiologist';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'radiology_technician';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'ophthalmologist';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'physiotherapist';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'dentist';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'dietician';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'it_admin';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'system_superuser';
