-- Finalize the exposed privilege boundary for the consolidated clinical continuity reader.
-- The RPC is intentionally authenticated-only; its clinical-role checks remain inside the function.

REVOKE ALL ON FUNCTION public.get_patient_care_continuity(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_care_continuity(UUID) TO authenticated;
