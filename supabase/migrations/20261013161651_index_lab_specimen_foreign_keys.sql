-- Add covering indexes for laboratory specimen foreign keys flagged by the database advisor.
-- Keep clinical access controls unchanged; this migration does not widen grants or RLS.
BEGIN;

CREATE INDEX IF NOT EXISTS idx_lab_specimens_collected_by
  ON public.lab_specimens (collected_by);

CREATE INDEX IF NOT EXISTS idx_lab_specimens_recollection_of_id
  ON public.lab_specimens (recollection_of_id);

CREATE INDEX IF NOT EXISTS idx_lab_specimens_rejected_by
  ON public.lab_specimens (rejected_by);

COMMIT;
