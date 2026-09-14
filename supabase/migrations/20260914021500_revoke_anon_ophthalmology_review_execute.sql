-- Restrict ophthalmology clinical review to authenticated callers.
-- The function already enforces admin/practitioner authorization internally.
REVOKE EXECUTE ON FUNCTION public.review_ophthalmology_exam(uuid, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.review_ophthalmology_exam(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_ophthalmology_exam(uuid, jsonb) TO authenticated;
