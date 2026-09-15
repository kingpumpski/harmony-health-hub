ALTER TABLE public.imaging_orders
  ADD COLUMN IF NOT EXISTS started_at timestamptz;

ALTER TABLE public.imaging_orders
  ADD COLUMN IF NOT EXISTS completed_at timestamptz;

UPDATE public.imaging_orders
SET started_at = created_at
WHERE status IN ('in_progress', 'completed')
  AND started_at IS NULL;

UPDATE public.imaging_orders
SET completed_at = updated_at
WHERE status = 'completed'
  AND completed_at IS NULL;

NOTIFY pgrst, 'reload schema';
