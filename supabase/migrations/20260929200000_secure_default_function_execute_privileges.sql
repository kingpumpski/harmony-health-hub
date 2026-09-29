-- Secure-by-default function execution for the exposed public schema.
--
-- New public functions must not become Data API-callable merely because
-- PostgreSQL grants EXECUTE to PUBLIC by default. Application RPCs must
-- explicitly grant the minimum required role after their authorization
-- contract is reviewed.
--
-- This migration is intentionally committed to the security branch first.
-- It must be validated in an isolated Supabase database before production
-- application.

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM authenticated;
