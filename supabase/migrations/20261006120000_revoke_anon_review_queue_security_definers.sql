-- Security reconciliation: review queues require an authenticated caller.
-- The functions already enforce auth.uid() and role/facility boundaries; anon execution
-- only creates an unnecessary exposed SECURITY DEFINER surface.

REVOKE EXECUTE ON FUNCTION public.get_pending_review_appointments() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_pending_specialist_referrals() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_pending_review_appointments() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_specialist_referrals() TO authenticated;

NOTIFY pgrst, 'reload schema';
