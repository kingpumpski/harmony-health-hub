REVOKE EXECUTE ON FUNCTION public.enqueue_notification(jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_notification(jsonb, text) TO service_role;