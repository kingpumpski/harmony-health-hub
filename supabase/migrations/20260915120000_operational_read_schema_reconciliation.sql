-- Reconcile legacy production tables with the operational read contracts used by
-- Theatre Board, Insurance Claims, Accounts Approvals and Pharmacy.
-- This migration is additive and idempotent. It restores missing columns and
-- foreign-key metadata required by PostgREST relationship expansion.

ALTER TABLE public.theatre_cases
  ADD COLUMN IF NOT EXISTS urgency TEXT NOT NULL DEFAULT 'elective';

ALTER TABLE public.theatre_cases
  DROP CONSTRAINT IF EXISTS theatre_cases_urgency_check;
ALTER TABLE public.theatre_cases
  ADD CONSTRAINT theatre_cases_urgency_check
  CHECK (urgency IN ('emergency','urgent','elective'));

ALTER TABLE public.insurance_claims
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.insurance_claims
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE public.prescriptions
  ADD COLUMN IF NOT EXISTS computed_quantity INTEGER;

CREATE INDEX IF NOT EXISTS idx_theatre_cases_urgency_schedule
  ON public.theatre_cases(urgency, scheduled_start);
CREATE INDEX IF NOT EXISTS idx_insurance_claims_created_at
  ON public.insurance_claims(created_at DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'service_orders_patient_id_fkey'
      AND conrelid = 'public.service_orders'::regclass
  ) THEN
    ALTER TABLE public.service_orders
      ADD CONSTRAINT service_orders_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'prescriptions_patient_id_fkey'
      AND conrelid = 'public.prescriptions'::regclass
  ) THEN
    ALTER TABLE public.prescriptions
      ADD CONSTRAINT prescriptions_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'insurance_claims_patient_id_fkey'
      AND conrelid = 'public.insurance_claims'::regclass
  ) THEN
    ALTER TABLE public.insurance_claims
      ADD CONSTRAINT insurance_claims_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'theatre_cases_patient_id_fkey'
      AND conrelid = 'public.theatre_cases'::regclass
  ) THEN
    ALTER TABLE public.theatre_cases
      ADD CONSTRAINT theatre_cases_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
