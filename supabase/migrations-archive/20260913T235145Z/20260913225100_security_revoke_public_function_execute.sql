-- PostgreSQL grants EXECUTE to PUBLIC by default for functions. Removing only
-- anon is insufficient when PUBLIC still owns the privilege. Remove PUBLIC
-- execution while preserving explicit authenticated/service_role grants.

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;

NOTIFY pgrst, 'reload schema';
