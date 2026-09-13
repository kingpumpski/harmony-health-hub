-- Front-end entry points now use guarded RPCs; prevent bypass through direct inserts.
REVOKE INSERT ON public.appointments FROM authenticated;
REVOKE INSERT ON public.triage_assessments FROM authenticated;

-- Reads remain available through existing RLS policies.
