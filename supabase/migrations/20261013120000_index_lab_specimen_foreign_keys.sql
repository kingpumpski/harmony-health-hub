-- Improve FK maintenance and selective lookups for laboratory specimen audit lineage.
-- Direct table access remains restricted; this migration does not widen grants or RLS.
BEGIN;

CREATE INDEX IF NOT EXISTS idx_lab_specimens_collected_by
  ON public.lab_specimens (collected_by)
  WHERE collected_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_lab_specimens_recollection_of_id
  ON public.lab_specimens (recollection_of_id)
  WHERE recollection_of_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_lab_specimens_rejected_by
  ON public.lab_specimens (rejected_by)
  WHERE rejected_by IS NOT NULL;

COMMIT;
