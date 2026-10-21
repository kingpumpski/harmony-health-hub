-- Radiology workflows begin before the later role-catalogue reconciliation.
-- Add this enum value in its own migration so following migrations can safely cast it.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'radiologist';
