-- The active facility context is application-readable but never directly mutable.
-- RLS already limits SELECT to the caller's own row or platform administrators.
grant select on table public.user_active_facilities to authenticated;
revoke insert, update, delete on table public.user_active_facilities from authenticated;
