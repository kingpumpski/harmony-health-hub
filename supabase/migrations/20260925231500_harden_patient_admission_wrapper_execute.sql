-- Tighten execution privileges for the legacy Patient Hub admission wrapper.
-- The canonical admission mutation is create_admission_workflow(), which owns
-- authentication, role authorization, facility/ward validation, and concurrency.
-- This wrapper is retained for compatibility but is not a client-facing RPC.
--
-- Do not remove the function yet: internal/server-side callers may still depend on it.
-- Removing authenticated execution eliminates the exposed SECURITY DEFINER surface
-- without changing the canonical admission workflow.

REVOKE EXECUTE ON FUNCTION public.create_patient_admission(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
