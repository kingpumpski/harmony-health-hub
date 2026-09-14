-- Reconcile the production insurance-claim financial invariants.
-- This migration is intentionally idempotent so it can be replayed on a fresh
-- database after the insurance claim contract migration.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'insurance_claims_amount_approved_check'
      AND conrelid = 'public.insurance_claims'::regclass
  ) THEN
    ALTER TABLE public.insurance_claims
      ADD CONSTRAINT insurance_claims_amount_approved_check
      CHECK (amount_approved IS NULL OR (amount_approved >= 0 AND amount_approved <= amount_claimed));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'insurance_claims_amount_paid_check'
      AND conrelid = 'public.insurance_claims'::regclass
  ) THEN
    ALTER TABLE public.insurance_claims
      ADD CONSTRAINT insurance_claims_amount_paid_check
      CHECK (amount_paid >= 0 AND amount_paid <= COALESCE(amount_approved, amount_claimed));
  END IF;
END $$;
