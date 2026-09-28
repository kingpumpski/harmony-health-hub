-- Tighten the triage table Data API boundary.
-- Triage creation is performed by the authenticated, role-checked RPC;
-- anonymous clients must not receive direct table DML privileges.
REVOKE ALL ON TABLE public.triage_assessments FROM anon;
REVOKE ALL ON TABLE public.triage_assessments FROM PUBLIC;

-- Preserve authenticated read access through the existing RLS SELECT policy.
GRANT SELECT ON TABLE public.triage_assessments TO authenticated;

-- Keep the privileged RPC on a deterministic system-first search path.
ALTER FUNCTION public.record_triage_assessment(
  UUID, INTEGER, INTEGER, INTEGER, NUMERIC, INTEGER, NUMERIC, NUMERIC,
  NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT
) SET search_path = pg_catalog, public;
