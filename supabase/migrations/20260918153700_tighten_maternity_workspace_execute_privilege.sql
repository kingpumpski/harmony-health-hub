-- Production reconciliation: prevent anonymous execution of the maternity
-- clinical workspace RPC. The application uses an authenticated session.
REVOKE EXECUTE ON FUNCTION public.get_maternity_workspace(INTEGER,UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_maternity_workspace(INTEGER,UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_maternity_workspace(INTEGER,UUID) TO authenticated;
