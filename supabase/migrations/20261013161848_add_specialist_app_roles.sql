-- Add specialist roles as enum values in an isolated migration.
-- Keep this migration separate: PostgreSQL requires a commit before new enum values
-- can be referenced by subsequent statements.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'physiotherapist';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'ophthalmologist';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'dentist';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'dietician';
