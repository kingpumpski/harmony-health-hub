-- Register radiologist before outside-lab RLS policies reference the role.
-- Keep this enum change in its own migration so later migrations can use the value.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'radiologist';
