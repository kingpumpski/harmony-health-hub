-- Phase 7: audited bulk-import job tracking.

CREATE TABLE IF NOT EXISTS public.bulk_import_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type TEXT NOT NULL CHECK (entity_type IN ('patients','pharmacy_inventory','icd_codes')),
  source_format TEXT NOT NULL CHECK (source_format IN ('csv','xlsx')),
  file_name TEXT,
  total_rows INTEGER NOT NULL DEFAULT 0 CHECK (total_rows >= 0),
  successful_rows INTEGER NOT NULL DEFAULT 0 CHECK (successful_rows >= 0),
  failed_rows INTEGER NOT NULL DEFAULT 0 CHECK (failed_rows >= 0),
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('processing','completed','completed_with_errors','failed')),
  errors JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

-- Reconcile pre-existing audit tables before indexing canonical columns.
-- Older installations use entity/filename/inserted_rows instead of the canonical
-- entity_type/file_name/successful_rows fields. Preserve the original audit rows.
ALTER TABLE public.bulk_import_jobs
  ADD COLUMN IF NOT EXISTS entity_type TEXT,
  ADD COLUMN IF NOT EXISTS source_format TEXT,
  ADD COLUMN IF NOT EXISTS file_name TEXT,
  ADD COLUMN IF NOT EXISTS successful_rows INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

DO $bulk_import_reconcile$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='bulk_import_jobs' AND column_name='entity'
  ) THEN
    EXECUTE $q$UPDATE public.bulk_import_jobs
      SET entity_type = CASE
        WHEN entity IN ('patients','pharmacy_inventory','icd_codes') THEN entity
        ELSE 'patients'
      END
      WHERE entity_type IS NULL$q$;
  ELSE
    UPDATE public.bulk_import_jobs SET entity_type='patients' WHERE entity_type IS NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='bulk_import_jobs' AND column_name='filename'
  ) THEN
    EXECUTE 'UPDATE public.bulk_import_jobs SET file_name = filename WHERE file_name IS NULL';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='bulk_import_jobs' AND column_name='inserted_rows'
  ) THEN
    EXECUTE 'UPDATE public.bulk_import_jobs SET successful_rows = inserted_rows WHERE successful_rows = 0 AND inserted_rows > 0';
  END IF;
END $bulk_import_reconcile$;

UPDATE public.bulk_import_jobs
SET source_format = COALESCE(source_format, 'csv'),
    successful_rows = COALESCE(successful_rows, 0),
    failed_rows = COALESCE(failed_rows, 0),
    errors = COALESCE(errors, '[]'::jsonb),
    status = CASE WHEN status IN ('processing','completed','completed_with_errors','failed')
      THEN status ELSE 'completed' END
WHERE source_format IS NULL OR status IS NULL;

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

ALTER TABLE public.bulk_import_jobs
  ADD CONSTRAINT bulk_import_jobs_row_counts_valid
  CHECK (successful_rows + failed_rows <= total_rows);
