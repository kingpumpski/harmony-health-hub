-- Keep enum additions isolated from migrations that use the new value.
-- PostgreSQL requires this migration to commit before ophthalmologist is referenced.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'ophthalmologist';
