-- Reconcile legacy bulk_import_jobs before Phase 7 indexes and constraints run.
-- Older installations created this table in May with entity/filename/inserted_rows,
-- so CREATE TABLE IF NOT EXISTS in the next migration cannot add the new columns.

ALTER TABLE IF EXISTS public.bulk_import_jobs
  ADD COLUMN IF NOT EXISTS entity_type TEXT,
  ADD COLUMN IF NOT EXISTS source_format TEXT,
  ADD COLUMN IF NOT EXISTS file_name TEXT,
  ADD COLUMN IF NOT EXISTS total_rows INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS successful_rows INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS failed_rows INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS errors JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'completed',
  ADD COLUMN IF NOT EXISTS created_by UUID,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

-- Preserve values from the legacy column names where they exist.
DO $bulk_import_compat$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='bulk_import_jobs' AND column_name='entity'
  ) THEN
    EXECUTE 'UPDATE public.bulk_import_jobs SET entity_type = COALESCE(entity_type, entity, ''patients'') WHERE entity_type IS NULL';
  ELSE
    UPDATE public.bulk_import_jobs SET entity_type = COALESCE(entity_type, 'patients') WHERE entity_type IS NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='bulk_import_jobs' AND column_name='filename'
  ) THEN
    EXECUTE 'UPDATE public.bulk_import_jobs SET file_name = COALESCE(file_name, filename) WHERE file_name IS NULL';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='bulk_import_jobs' AND column_name='inserted_rows'
  ) THEN
    EXECUTE 'UPDATE public.bulk_import_jobs SET successful_rows = inserted_rows WHERE successful_rows = 0 AND inserted_rows > 0';
  END IF;
END
$bulk_import_compat$;

UPDATE public.bulk_import_jobs
SET entity_type = COALESCE(entity_type, 'patients'),
    source_format = COALESCE(source_format, 'csv'),
    successful_rows = COALESCE(successful_rows, 0),
    failed_rows = COALESCE(failed_rows, 0),
    errors = COALESCE(errors, '[]'::jsonb),
    status = CASE
      WHEN status IN ('processing','completed','completed_with_errors','failed') THEN status
      ELSE 'completed'
    END
WHERE entity_type IS NULL OR source_format IS NULL OR successful_rows IS NULL
   OR failed_rows IS NULL OR errors IS NULL OR status IS NULL;

ALTER TABLE public.bulk_import_jobs
  ALTER COLUMN entity_type SET NOT NULL,
  ALTER COLUMN source_format SET DEFAULT 'csv',
  ALTER COLUMN source_format SET NOT NULL,
  ALTER COLUMN successful_rows SET DEFAULT 0,
  ALTER COLUMN successful_rows SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bulk_import_jobs_created_by_time
  ON public.bulk_import_jobs(created_by, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bulk_import_jobs_entity_status
  ON public.bulk_import_jobs(entity_type, status, created_at DESC);

ALTER TABLE public.bulk_import_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admins manage bulk import jobs" ON public.bulk_import_jobs;
CREATE POLICY "admins manage bulk import jobs"
  ON public.bulk_import_jobs FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "users read own bulk import jobs" ON public.bulk_import_jobs;
CREATE POLICY "users read own bulk import jobs"
  ON public.bulk_import_jobs FOR SELECT TO authenticated
  USING (created_by = auth.uid() OR public.has_role(auth.uid(),'admin'));
