-- Expand the migration foundation for Ghana clinical reference data, services/tariffs,
-- and continuity-of-care records imported from legacy systems.
-- Applied to production through the Supabase migration runner.

CREATE TABLE IF NOT EXISTS public.data_migration_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type TEXT NOT NULL,
  source_system TEXT NOT NULL,
  source_version TEXT,
  file_name TEXT,
  source_format TEXT NOT NULL DEFAULT 'csv' CHECK (source_format IN ('csv','xlsx','json','other')),
  total_rows INTEGER NOT NULL DEFAULT 0 CHECK (total_rows >= 0),
  staged_rows INTEGER NOT NULL DEFAULT 0 CHECK (staged_rows >= 0),
  accepted_rows INTEGER NOT NULL DEFAULT 0 CHECK (accepted_rows >= 0),
  rejected_rows INTEGER NOT NULL DEFAULT 0 CHECK (rejected_rows >= 0),
  status TEXT NOT NULL DEFAULT 'staged' CHECK (status IN ('staged','validating','ready','importing','completed','completed_with_errors','failed')),
  mapping_profile TEXT,
  validation_errors JSONB NOT NULL DEFAULT '[]'::jsonb,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  approved_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.data_migration_rows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id UUID NOT NULL REFERENCES public.data_migration_batches(id) ON DELETE CASCADE,
  source_row_number INTEGER NOT NULL,
  source_key TEXT,
  raw_data JSONB NOT NULL,
  normalized_data JSONB,
  row_status TEXT NOT NULL DEFAULT 'staged' CHECK (row_status IN ('staged','validated','accepted','rejected','imported','duplicate')),
  rejection_reason TEXT,
  target_table TEXT,
  target_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(batch_id, source_row_number)
);

CREATE TABLE IF NOT EXISTS public.legacy_clinical_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id UUID REFERENCES public.data_migration_batches(id) ON DELETE SET NULL,
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  source_system TEXT NOT NULL,
  source_patient_key TEXT,
  source_record_id TEXT,
  record_type TEXT NOT NULL,
  occurred_at TIMESTAMPTZ,
  author_name TEXT,
  department TEXT,
  encounter_reference TEXT,
  clinical_summary TEXT,
  raw_record JSONB NOT NULL DEFAULT '{}'::jsonb,
  migration_status TEXT NOT NULL DEFAULT 'staged' CHECK (migration_status IN ('staged','matched','imported','rejected','needs_review')),
  imported_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  imported_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_data_migration_batches_entity_status ON public.data_migration_batches(entity_type,status,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_data_migration_rows_batch_status ON public.data_migration_rows(batch_id,row_status,source_row_number);
CREATE INDEX IF NOT EXISTS idx_legacy_clinical_records_patient_time ON public.legacy_clinical_records(patient_id,occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_legacy_clinical_records_source_key ON public.legacy_clinical_records(source_system,source_patient_key,source_record_id);

ALTER TABLE public.data_migration_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_migration_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legacy_clinical_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage migration batches" ON public.data_migration_batches;
CREATE POLICY "admins manage migration batches" ON public.data_migration_batches FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "admins manage migration rows" ON public.data_migration_rows;
CREATE POLICY "admins manage migration rows" ON public.data_migration_rows FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "clinical read legacy records" ON public.legacy_clinical_records;
CREATE POLICY "clinical read legacy records" ON public.legacy_clinical_records FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse'));
DROP POLICY IF EXISTS "admins manage legacy records" ON public.legacy_clinical_records;
CREATE POLICY "admins manage legacy records" ON public.legacy_clinical_records FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

ALTER TABLE public.service_tariffs ADD COLUMN IF NOT EXISTS source_standard TEXT;
ALTER TABLE public.service_tariffs ADD COLUMN IF NOT EXISTS effective_from DATE;
ALTER TABLE public.service_tariffs ADD COLUMN IF NOT EXISTS effective_to DATE;
ALTER TABLE public.service_tariffs ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'GHS';
ALTER TABLE public.service_tariffs ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_service_tariffs_source_effective ON public.service_tariffs(source_standard,effective_from,effective_to,active);

CREATE TABLE IF NOT EXISTS public.system_master_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain TEXT NOT NULL,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  source_system TEXT,
  source_version TEXT,
  effective_from DATE,
  effective_to DATE,
  active BOOLEAN NOT NULL DEFAULT true,
  attributes JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(domain,code,source_system)
);
ALTER TABLE public.system_master_data ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "authenticated read master data" ON public.system_master_data;
CREATE POLICY "authenticated read master data" ON public.system_master_data FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "admins manage master data" ON public.system_master_data;
CREATE POLICY "admins manage master data" ON public.system_master_data FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

CREATE OR REPLACE FUNCTION public.create_data_migration_batch(_entity_type TEXT,_source_system TEXT,_source_version TEXT DEFAULT NULL,_file_name TEXT DEFAULT NULL,_source_format TEXT DEFAULT 'csv',_total_rows INTEGER DEFAULT 0)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  INSERT INTO public.data_migration_batches(entity_type,source_system,source_version,file_name,source_format,total_rows,created_by)
  VALUES (_entity_type,_source_system,_source_version,_file_name,_source_format,COALESCE(_total_rows,0),auth.uid()) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.create_data_migration_batch(TEXT,TEXT,TEXT,TEXT,TEXT,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_data_migration_batch(TEXT,TEXT,TEXT,TEXT,TEXT,INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.stage_data_migration_rows(_batch_id UUID,_rows JSONB)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_count INTEGER := 0; v_item JSONB; v_row INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.data_migration_batches WHERE id=_batch_id) THEN RAISE EXCEPTION 'Migration batch not found'; END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(_rows,'[]'::jsonb)) LOOP
    v_row := v_row + 1;
    INSERT INTO public.data_migration_rows(batch_id,source_row_number,source_key,raw_data)
    VALUES (_batch_id,v_row,COALESCE(v_item->>'source_key',v_item->>'patient_code',v_item->>'id'),v_item)
    ON CONFLICT (batch_id,source_row_number) DO UPDATE SET raw_data=EXCLUDED.raw_data,row_status='staged',rejection_reason=NULL;
    v_count := v_count + 1;
  END LOOP;
  UPDATE public.data_migration_batches SET staged_rows=v_count,status='staged' WHERE id=_batch_id;
  RETURN v_count;
END; $$;
REVOKE ALL ON FUNCTION public.stage_data_migration_rows(UUID,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.stage_data_migration_rows(UUID,JSONB) TO authenticated;

INSERT INTO public.system_master_data(domain,code,name,description,source_system,active)
VALUES
('diagnosis_standard','GH-STG','Ghana Standard Treatment Guidelines','Ghana clinical diagnosis/treatment reference metadata; load the licensed/current source dataset through the migration workspace.','Ghana MoH',true),
('service_catalogue','SERVICE','Service catalogue','Facility service definitions and identifiers used by billing, orders and reporting.','Harmony',true),
('data_migration','LEGACY_CLINICAL_RECORD','Legacy clinical record','Continuity-of-care record staged from an external hospital/clinic system before reconciliation into native clinical workflows.','External system',true)
ON CONFLICT (domain,code,source_system) DO NOTHING;
