-- Add the application-level IT Admin role before dependent permission rows are created.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'it_admin';
