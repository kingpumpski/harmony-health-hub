BEGIN;

-- Bring the production legacy bulk-import table forward without discarding
-- historical values from entity/filename/inserted_rows.
ALTER TABLE public.bulk_import_jobs
  ADD COLUMN IF NOT EXISTS entity_type TEXT,
  ADD COLUMN IF NOT EXISTS source_format TEXT,
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

UPDATE public.bulk_import_jobs
SET source_format = CASE
  WHEN right(lower(coalesce(file_name, '')), 5) = '.xlsx' THEN 'xlsx'
  WHEN right(lower(coalesce(file_name, '')), 4) = '.csv' THEN 'csv'
  ELSE NULL
END
WHERE source_format IS NULL;

DO $bulk_import_source_format$
BEGIN
  IF EXISTS (SELECT 1 FROM public.bulk_import_jobs WHERE source_format IS NULL) THEN
    RAISE EXCEPTION 'Bulk import history contains rows without a verifiable source format; reconcile from original filenames before proceeding.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.bulk_import_jobs WHERE entity_type IS NULL) THEN
    RAISE EXCEPTION 'Bulk import history contains rows without a verifiable entity type; reconcile from original entity values before proceeding.';
  END IF;
END
$bulk_import_source_format$;

UPDATE public.bulk_import_jobs
SET completed_at = created_at
WHERE completed_at IS NULL
  AND status IS DISTINCT FROM 'processing';

ALTER TABLE public.bulk_import_jobs
  ALTER COLUMN source_format SET DEFAULT 'csv',
  ALTER COLUMN source_format SET NOT NULL,
  ALTER COLUMN entity_type SET NOT NULL;

ALTER TABLE public.bulk_import_jobs
  DROP CONSTRAINT IF EXISTS bulk_import_jobs_source_format_check;
ALTER TABLE public.bulk_import_jobs
  ADD CONSTRAINT bulk_import_jobs_source_format_check
  CHECK (source_format IN ('csv','xlsx'));

ALTER TABLE public.bulk_import_jobs
  DROP CONSTRAINT IF EXISTS bulk_import_jobs_entity_type_check;
ALTER TABLE public.bulk_import_jobs
  ADD CONSTRAINT bulk_import_jobs_entity_type_check
  CHECK (entity_type IN ('patients','pharmacy_inventory','icd_codes','staff'));

CREATE INDEX IF NOT EXISTS idx_bulk_import_jobs_created_by_time
  ON public.bulk_import_jobs(created_by, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bulk_import_jobs_entity_status
  ON public.bulk_import_jobs(entity_type, status, created_at DESC);

-- Add indexes for the four verified foreign-key columns that had no supporting
-- index in the live production catalog.
CREATE INDEX IF NOT EXISTS idx_hr_employees_archived_by
  ON public.hr_employees(archived_by);
CREATE INDEX IF NOT EXISTS idx_lab_result_attachments_uploaded_by
  ON public.lab_result_attachments(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_lab_test_group_items_test_id
  ON public.lab_test_group_items(test_id);
CREATE INDEX IF NOT EXISTS idx_lab_test_groups_created_by
  ON public.lab_test_groups(created_by);

-- The panel manager deliberately uses guarded SECURITY DEFINER RPCs. Direct
-- PostgREST access to the underlying tables is not part of the client contract.
REVOKE ALL ON TABLE public.lab_test_groups, public.lab_test_group_items
  FROM PUBLIC, anon, authenticated;
ALTER TABLE public.lab_test_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_test_group_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS lab_test_groups_deny_direct_api ON public.lab_test_groups;
CREATE POLICY lab_test_groups_deny_direct_api
  ON public.lab_test_groups AS RESTRICTIVE
  FOR ALL TO authenticated
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS lab_test_group_items_deny_direct_api ON public.lab_test_group_items;
CREATE POLICY lab_test_group_items_deny_direct_api
  ON public.lab_test_group_items AS RESTRICTIVE
  FOR ALL TO authenticated
  USING (false)
  WITH CHECK (false);

COMMENT ON TABLE public.lab_test_groups IS
  'Direct client table access is denied; use facility-scoped SECURITY DEFINER laboratory panel RPCs.';
COMMENT ON TABLE public.lab_test_group_items IS
  'Direct client table access is denied; use facility-scoped SECURITY DEFINER laboratory panel RPCs.';

-- Trigger functions are invoked by their triggers, not as client RPCs.
ALTER FUNCTION public.ensure_updated_at() SET search_path = pg_catalog;
REVOKE ALL ON FUNCTION public.ensure_updated_at()
  FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION public.ensure_updated_at() IS
  'Internal trigger-only updated_at helper; direct client execution is revoked.';

-- Remove only duplicate foreign keys with identical definitions. Keep the
-- canonical *_service_order_id_fkey constraints enforcing the same relation.
ALTER TABLE IF EXISTS public.billing_overrides
  DROP CONSTRAINT IF EXISTS billing_overrides_service_order_fk;
ALTER TABLE IF EXISTS public.department_queues
  DROP CONSTRAINT IF EXISTS department_queues_service_order_fk;

-- Cover the four production foreign keys reported by the advisor. These
-- tables are currently small, and each index supports parent-row updates/deletes.
CREATE INDEX IF NOT EXISTS idx_hr_employees_archived_by
  ON public.hr_employees(archived_by);
CREATE INDEX IF NOT EXISTS idx_lab_result_attachments_uploaded_by
  ON public.lab_result_attachments(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_lab_test_group_items_test_id
  ON public.lab_test_group_items(test_id);
CREATE INDEX IF NOT EXISTS idx_lab_test_groups_created_by
  ON public.lab_test_groups(created_by);

-- Keep idx_lab_result_attachments_lab_result_id; this second index has the
-- identical btree key and provides no additional query coverage.
DROP INDEX IF EXISTS public.lab_result_attachments_result_idx;

COMMIT;
