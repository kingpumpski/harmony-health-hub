-- Audit logs are append-only server-owned surfaces.
-- Application actors must use the existing audit helpers/triggers; direct client DML is prohibited.

REVOKE INSERT, UPDATE, DELETE ON public.system_audit_log FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.audit_logs FROM authenticated;

REVOKE ALL ON FUNCTION public.record_system_audit(TEXT,TEXT,TEXT,UUID,TEXT,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_system_audit(TEXT,TEXT,TEXT,UUID,TEXT,JSONB) TO authenticated;
