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
