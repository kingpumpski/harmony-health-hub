-- Harden legacy AI-session SECURITY DEFINER routines with a trusted search path.
-- Preserve function signatures, grants, and behavior; only pin name resolution.
ALTER FUNCTION public.complete_ai_clinical_session(uuid, jsonb, text, text, jsonb)
  SET search_path = pg_catalog, public;

ALTER FUNCTION public.validate_ai_clinical_session_state()
  SET search_path = pg_catalog, public;
