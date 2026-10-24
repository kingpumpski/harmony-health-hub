-- Secure-by-default function execution for the exposed public schema.
--
-- New public functions must not become Data API-callable merely because
-- PostgreSQL grants EXECUTE to PUBLIC by default. Application RPCs must
-- explicitly grant the minimum required role after their authorization
-- contract is reviewed.
--
-- This migration is intentionally committed to the security branch first.
-- It must be validated in an isolated Supabase environment before production.
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

-- Some migration runners are not members of supabase_admin and cannot
-- alter that role's defaults. Apply the same policy only when the runner is
-- authorized to change the role; postgres-owned migrations are covered above.
DO $supabase_admin_default_privileges$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'supabase_admin')
     AND (current_user = 'supabase_admin'
          OR pg_catalog.pg_has_role(current_user, 'supabase_admin', 'MEMBER')) THEN
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC';
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon';
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM authenticated';
  END IF;
END;
$supabase_admin_default_privileges$;
