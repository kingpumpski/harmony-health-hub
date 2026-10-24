-- Forward repair for installations where phase 2 is already recorded as applied.
-- Preserve the historical queue order by deriving queued_at from created_at.
ALTER TABLE public.department_queues
  ADD COLUMN IF NOT EXISTS queued_at TIMESTAMPTZ;

UPDATE public.department_queues
SET queued_at = COALESCE(queued_at, created_at, now())
WHERE queued_at IS NULL;

ALTER TABLE public.department_queues
  ALTER COLUMN queued_at SET DEFAULT now(),
  ALTER COLUMN queued_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_department_queues_work
  ON public.department_queues(department, status, queued_at);
