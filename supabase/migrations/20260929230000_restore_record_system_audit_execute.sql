-- Restore the authenticated RPC execution boundary required by client-side audit writes.
-- The function itself remains security-definer and requires auth.uid(); anon stays denied.
grant execute on function public.record_system_audit(text, text, text, uuid, text, jsonb) to authenticated;
revoke execute on function public.record_system_audit(text, text, text, uuid, text, jsonb) from anon;
