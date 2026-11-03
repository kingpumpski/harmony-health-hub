-- Add the ophthalmologist enum value before the first migration that references it.
-- Keep this isolated so PostgreSQL commits the new enum value before later policies use it.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'ophthalmologist';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'radiologist';
