-- Add the ophthalmology specialist role before ophthalmology policies and RPCs
-- reference it. A separate migration boundary makes the new enum value usable by
-- subsequent migrations on PostgreSQL versions that disallow same-transaction use.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'ophthalmologist';
