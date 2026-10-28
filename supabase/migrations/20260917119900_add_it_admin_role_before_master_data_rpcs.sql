-- The master-data/RPC migration uses it_admin before the later role-support migration.
-- Introduce the enum label in its own earlier migration so subsequent policies can cast it.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'it_admin';
