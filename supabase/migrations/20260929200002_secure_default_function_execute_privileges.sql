-- Secure-by-default function execution for the exposed public schema.
--
-- New public functions must not become Data API-callable merely because
-- PostgreSQL grants EXECUTE to PUBLIC by default. Application RPCs must
-- explicitly grant the minimum required role after their authorization
-- contract is reviewed.
--
-- Scope: functions created by the postgres migration owner. Other function-
-- owning roles must receive equivalent policy through their own audited
-- migrations.

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM authenticated;

-- Supabase-managed migrations can also be created by supabase_admin.
-- Only change that role's defaults when the current migration owner is
-- authorized to manage its default privileges. Local Supabase and some
-- hosted migration connections intentionally do not grant this membership.
DO $supabase_admin_default_privileges$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'supabase_admin'
  ) AND (
    current_user = 'supabase_admin'
    OR pg_catalog.pg_has_role(current_user, 'supabase_admin', 'MEMBER')
  ) THEN
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC';
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon';
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM authenticated';
  ELSE
    RAISE NOTICE 'Skipping supabase_admin default-privilege changes: current role % cannot manage that role''s defaults. Keep supabase_admin-owned functions under explicit audited grants.', current_user;
  END IF;
END;
$supabase_admin_default_privileges$;
