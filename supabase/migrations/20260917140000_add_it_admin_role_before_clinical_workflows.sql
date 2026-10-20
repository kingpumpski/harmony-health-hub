-- The clinical admission/referral migration references this enum value.
-- Add it in an earlier migration so fresh installs replay in dependency order.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'it_admin';
