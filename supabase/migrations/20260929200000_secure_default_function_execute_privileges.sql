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

-- Supabase-managed migrations can also be created by supabase_admin.
-- Keep that owner role secure-by-default as well.
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM authenticated;
