-- Laboratory clinical state changes are now routed through audited SECURITY DEFINER RPCs.
-- The compatibility grants from 20260912205000 are no longer required by the
-- reconciled Laboratory UI and would permit clients to bypass workflow transitions.

REVOKE INSERT, UPDATE, DELETE ON public.lab_orders FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.lab_results FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.collect_lab_sample(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) FROM anon;
REVOKE EXECUTE ON FUNCTION public.approve_lab_result(UUID) FROM anon;

-- Catalogue linkage is also a clinical workflow operation and must use the
-- audited server transition rather than a client-side foreign-key update.
REVOKE UPDATE ON public.lab_orders FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.attach_lab_catalogue_to_order(UUID,UUID) FROM anon;
