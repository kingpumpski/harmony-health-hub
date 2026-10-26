-- Ensure the IT Admin role exists before clinical workflows reference it.
-- Keep enum addition isolated from migrations that cast/use the new label:
-- PostgreSQL requires the enum change to commit before dependent statements run.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'it_admin';
