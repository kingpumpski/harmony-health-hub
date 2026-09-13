-- Transitional compatibility for existing laboratory clients.
-- RLS remains authoritative; new clients should use the secure transition RPCs.
GRANT UPDATE ON public.lab_orders TO authenticated;
GRANT INSERT, UPDATE ON public.lab_results TO authenticated;

-- The new server transitions remain the canonical audited path.
REVOKE EXECUTE ON FUNCTION public.collect_lab_sample(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) FROM anon;
REVOKE EXECUTE ON FUNCTION public.approve_lab_result(UUID) FROM anon;
