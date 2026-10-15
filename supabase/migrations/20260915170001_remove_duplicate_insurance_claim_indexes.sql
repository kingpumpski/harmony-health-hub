-- Remove exact duplicate indexes introduced during schema reconciliation.
-- Keep the original idx_* names used by the canonical application schema.
-- This migration is intentionally isolated from production execution until the
-- approved Supabase migration workflow reconciles remote migration history.

DROP INDEX IF EXISTS public.insurance_claims_invoice_id_idx;
DROP INDEX IF EXISTS public.insurance_claims_patient_id_idx;
