-- Remove anonymous execution from clinical SECURITY DEFINER RPCs.
-- These functions already enforce authenticated application roles internally;
-- anonymous PostgREST execution is therefore an unnecessary attack surface.

REVOKE EXECUTE ON FUNCTION public.create_nursing_care_plan(uuid, text, text, text, text, uuid, uuid) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_theatre_case(uuid, text, timestamp with time zone, text, text, uuid, uuid, uuid) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_transfusion_record(uuid, text, text, text, boolean, uuid) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.transition_emergency_case(uuid, text, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.transition_theatre_case(uuid, text, text) FROM anon, PUBLIC;
