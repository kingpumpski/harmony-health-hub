-- The radiologist enum value must exist before outside-lab storage policies use it.
-- The later historical migration remains idempotent for databases that already applied it.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'radiologist';
