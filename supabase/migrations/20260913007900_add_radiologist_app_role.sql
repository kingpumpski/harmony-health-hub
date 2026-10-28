-- Add the radiologist role before outside-laboratory policies cast the role literal.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'radiologist';
