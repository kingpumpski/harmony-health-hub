-- Reconcile the production pharmacy inventory contract before the server-authoritative
-- dispensing RPCs reference the active flag. Existing stock rows remain unchanged.
ALTER TABLE public.pharmacy_inventory
  ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT TRUE;
