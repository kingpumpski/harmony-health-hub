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

-- Reconcile the original bulk_import_jobs shape before adding indexes.
-- The legacy table used entity/filename/inserted_rows and did not include
-- entity_type/source_format/file_name/successful_rows/completed_at.
ALTER TABLE public.bulk_import_jobs
  ADD COLUMN IF NOT EXISTS entity_type TEXT,
  ADD COLUMN IF NOT EXISTS source_format TEXT NOT NULL DEFAULT 'csv',
  ADD COLUMN IF NOT EXISTS file_name TEXT,
  ADD COLUMN IF NOT EXISTS successful_rows INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

DO $bulk_import_legacy_columns$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='bulk_import_jobs' AND column_name='entity'
  ) THEN
    EXECUTE $sql$
      UPDATE public.bulk_import_jobs
      SET entity_type = CASE entity
        WHEN 'patients' THEN 'patients'
        WHEN 'pharmacy_inventory' THEN 'pharmacy_inventory'
        WHEN 'icd_codes' THEN 'icd_codes'
        WHEN 'staff' THEN 'staff'
        ELSE entity
      END
      WHERE entity_type IS NULL
    $sql$;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='bulk_import_jobs' AND column_name='filename'
  ) THEN
    EXECUTE 'UPDATE public.bulk_import_jobs SET file_name = filename WHERE file_name IS NULL AND filename IS NOT NULL';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='bulk_import_jobs' AND column_name='inserted_rows'
  ) THEN
    EXECUTE 'UPDATE public.bulk_import_jobs SET successful_rows = inserted_rows WHERE successful_rows = 0 AND inserted_rows IS NOT NULL';
  END IF;
END
$bulk_import_legacy_columns$;

ALTER TABLE public.bulk_import_jobs
  ALTER COLUMN entity_type SET NOT NULL;

ALTER TABLE public.bulk_import_jobs
  DROP CONSTRAINT IF EXISTS bulk_import_jobs_entity_type_check;
ALTER TABLE public.bulk_import_jobs
  ADD CONSTRAINT bulk_import_jobs_entity_type_check
  CHECK (entity_type IN ('patients','pharmacy_inventory','icd_codes','staff'));

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

DO $bulk_import_row_counts$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.bulk_import_jobs'::regclass
      AND conname = 'bulk_import_jobs_row_counts_valid'
  ) THEN
    ALTER TABLE public.bulk_import_jobs
      ADD CONSTRAINT bulk_import_jobs_row_counts_valid
      CHECK (successful_rows + failed_rows <= total_rows);
  END IF;
END;
$bulk_import_row_counts$;

