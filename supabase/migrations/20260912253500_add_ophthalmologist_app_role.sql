-- Add the specialist ophthalmology role before ophthalmology policies/functions
-- cast role literals to public.app_role. Keep this in its own migration so the
-- new enum value is committed before later migrations use it.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'ophthalmologist';
