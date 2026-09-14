-- Harden direct mutation of anesthesia and inpatient-review records.
-- These clinical records remain readable through existing RLS policies;
-- mutation authority is reserved for server-side workflow paths.

BEGIN;

REVOKE INSERT, UPDATE, DELETE ON public.anesthetic_assessments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.inpatient_reviews FROM authenticated;

COMMIT;
