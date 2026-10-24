-- Restore foundational reference/operational tables before the historical
-- 20260910215228 RLS migration applies grants and policies to them. All changes
-- are additive so partially provisioned installations retain existing rows.
BEGIN;

CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  action text,
  table_name text,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.audit_logs
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS action text,
  ADD COLUMN IF NOT EXISTS table_name text,
  ADD COLUMN IF NOT EXISTS record_id text,
  ADD COLUMN IF NOT EXISTS old_data jsonb,
  ADD COLUMN IF NOT EXISTS new_data jsonb,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
UPDATE public.audit_logs SET id = gen_random_uuid() WHERE id IS NULL;
ALTER TABLE public.audit_logs ALTER COLUMN id SET DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX IF NOT EXISTS audit_logs_id_legacy_uidx ON public.audit_logs(id);

CREATE TABLE IF NOT EXISTS public.sync_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payload jsonb,
  synced boolean DEFAULT false,
  table_name text
);
ALTER TABLE public.sync_queue
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS payload jsonb,
  ADD COLUMN IF NOT EXISTS synced boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS table_name text;
UPDATE public.sync_queue SET id = gen_random_uuid() WHERE id IS NULL;
ALTER TABLE public.sync_queue ALTER COLUMN id SET DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX IF NOT EXISTS sync_queue_id_legacy_uidx ON public.sync_queue(id);

CREATE TABLE IF NOT EXISTS public.lab_tests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_name text,
  loinc_code text,
  specimen text,
  normal_range text,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.lab_tests
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS test_name text,
  ADD COLUMN IF NOT EXISTS loinc_code text,
  ADD COLUMN IF NOT EXISTS specimen text,
  ADD COLUMN IF NOT EXISTS normal_range text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
UPDATE public.lab_tests SET id = gen_random_uuid() WHERE id IS NULL;
ALTER TABLE public.lab_tests ALTER COLUMN id SET DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX IF NOT EXISTS lab_tests_id_legacy_uidx ON public.lab_tests(id);

COMMIT;
