-- Reconcile the original pharmacy inventory table with the lifecycle RPCs.
-- Existing stock remains available by default; explicit deactivation is additive.
ALTER TABLE public.pharmacy_inventory
  ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true;
