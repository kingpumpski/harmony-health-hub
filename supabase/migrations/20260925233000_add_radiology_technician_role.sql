-- Add the imaging technologist role referenced by the imaging authorization boundary.
-- Kept idempotent so deployments can safely replay the migration.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'radiology_technician';
