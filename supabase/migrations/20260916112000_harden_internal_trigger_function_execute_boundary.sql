-- Keep trigger-only SECURITY DEFINER helpers outside the client-callable RPC surface.
-- These functions are invoked by table triggers, not by PostgREST clients.
REVOKE EXECUTE ON FUNCTION public.generate_patient_code() FROM authenticated, anon, public;
