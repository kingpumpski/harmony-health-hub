-- Introduce the IT administrator enum value before the admission/referral
-- lifecycle migration compiles functions and policies that reference it.
-- Keep this migration isolated so PostgreSQL commits the enum value first.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'it_admin';
