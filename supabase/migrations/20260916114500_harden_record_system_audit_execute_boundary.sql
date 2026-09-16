REVOKE EXECUTE ON FUNCTION public.record_system_audit(text, text, text, uuid, text, jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.record_system_audit(text, text, text, uuid, text, jsonb) FROM anon;
