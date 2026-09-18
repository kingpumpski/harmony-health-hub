-- Add the radiologist role used by the dedicated radiology workflow.
-- Repository migration only; apply through the normal Supabase migration pipeline.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'radiologist';
