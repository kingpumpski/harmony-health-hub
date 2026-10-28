-- Reconcile the timestamp required by inpatient review queue indexes.
-- Legacy installations may already have inpatient_reviews without seen_at.
ALTER TABLE public.inpatient_reviews
  ADD COLUMN IF NOT EXISTS seen_at TIMESTAMPTZ NOT NULL DEFAULT now();

NOTIFY pgrst, 'reload schema';
