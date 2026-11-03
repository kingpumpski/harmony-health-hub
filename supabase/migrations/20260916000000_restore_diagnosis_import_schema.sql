-- Restore the diagnosis terminology and staged-import schema that exists in the
-- connected production database but was absent from the replayable migration chain.
-- This migration must precede 20260916103212_add_missing_foreign_key_indexes.sql.

CREATE TABLE IF NOT EXISTS public.diagnosis_standards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  jurisdiction text NOT NULL,
  version text,
  publisher text,
  source_uri text,
  effective_from date,
  effective_to date,
  is_default boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.stg_diagnoses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  standard_id uuid NOT NULL REFERENCES public.diagnosis_standards(id) ON DELETE CASCADE,
  code text NOT NULL,
  display_name text NOT NULL,
  description text,
  category text,
  synonyms text[] NOT NULL DEFAULT '{}'::text[],
  icd10_code_id uuid REFERENCES public.icd_codes(id) ON DELETE SET NULL,
  source_reference text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT stg_diagnoses_standard_id_code_key UNIQUE (standard_id, code)
);

CREATE TABLE IF NOT EXISTS public.diagnosis_standard_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stg_diagnosis_id uuid NOT NULL REFERENCES public.stg_diagnoses(id) ON DELETE CASCADE,
  icd10_code_id uuid NOT NULL REFERENCES public.icd_codes(id) ON DELETE CASCADE,
  mapping_type text NOT NULL DEFAULT 'exact'
    CHECK (mapping_type IN ('exact','broader','narrower','related','approximate')),
  confidence numeric CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  source_reference text,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT diagnosis_standard_mappings_stg_diagnosis_id_icd10_code_id_key
    UNIQUE (stg_diagnosis_id, icd10_code_id)
);

CREATE TABLE IF NOT EXISTS public.diagnosis_import_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  standard_id uuid REFERENCES public.diagnosis_standards(id) ON DELETE RESTRICT,
  file_name text,
  source_format text NOT NULL DEFAULT 'xlsx',
  source_version text,
  assessment_only boolean NOT NULL DEFAULT true,
  status text NOT NULL DEFAULT 'assessed'
    CHECK (status IN ('assessed','validated','approved','importing','completed','completed_with_errors','failed','cancelled')),
  total_sheets integer NOT NULL DEFAULT 0,
  total_rows integer NOT NULL DEFAULT 0,
  accepted_rows integer NOT NULL DEFAULT 0,
  rejected_rows integer NOT NULL DEFAULT 0,
  duplicate_rows integer NOT NULL DEFAULT 0,
  unmapped_rows integer NOT NULL DEFAULT 0,
  validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  sheet_assessments jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  approved_at timestamptz,
  completed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.diagnosis_import_rows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES public.diagnosis_import_batches(id) ON DELETE CASCADE,
  sheet_name text NOT NULL,
  source_row_number integer NOT NULL CHECK (source_row_number > 0),
  source_code text,
  display_name text,
  description text,
  category text,
  synonyms text[] NOT NULL DEFAULT '{}'::text[],
  icd10_code text,
  normalized_key text NOT NULL,
  row_status text NOT NULL DEFAULT 'pending'
    CHECK (row_status IN ('pending','accepted','rejected','duplicate','unmapped')),
  rejection_reason text,
  icd10_code_id uuid REFERENCES public.icd_codes(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS diagnosis_standards_code_key
  ON public.diagnosis_standards(code);
CREATE INDEX IF NOT EXISTS idx_stg_diagnoses_name
  ON public.stg_diagnoses USING gin (to_tsvector('simple', display_name));
CREATE INDEX IF NOT EXISTS idx_stg_diagnoses_standard_code
  ON public.stg_diagnoses(standard_id, code);
CREATE INDEX IF NOT EXISTS stg_diagnoses_code_idx ON public.stg_diagnoses(code);
CREATE INDEX IF NOT EXISTS stg_diagnoses_display_name_idx ON public.stg_diagnoses(display_name);
CREATE INDEX IF NOT EXISTS stg_diagnoses_standard_active_idx ON public.stg_diagnoses(standard_id, is_active);
CREATE INDEX IF NOT EXISTS idx_diagnosis_standard_mappings_icd
  ON public.diagnosis_standard_mappings(icd10_code_id);
CREATE INDEX IF NOT EXISTS idx_diagnosis_standard_mappings_stg
  ON public.diagnosis_standard_mappings(stg_diagnosis_id);
CREATE INDEX IF NOT EXISTS diagnosis_import_batches_created_at_idx
  ON public.diagnosis_import_batches(created_at DESC);
CREATE INDEX IF NOT EXISTS diagnosis_import_batches_standard_idx
  ON public.diagnosis_import_batches(standard_id);
CREATE INDEX IF NOT EXISTS diagnosis_import_batches_status_idx
  ON public.diagnosis_import_batches(status);
CREATE INDEX IF NOT EXISTS diagnosis_import_rows_batch_idx
  ON public.diagnosis_import_rows(batch_id);
CREATE INDEX IF NOT EXISTS diagnosis_import_rows_key_idx
  ON public.diagnosis_import_rows(batch_id, normalized_key);
CREATE INDEX IF NOT EXISTS diagnosis_import_rows_status_idx
  ON public.diagnosis_import_rows(row_status);

ALTER TABLE public.diagnosis_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stg_diagnoses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_standard_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_import_rows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS diagnosis_standards_authenticated_read ON public.diagnosis_standards;
CREATE POLICY diagnosis_standards_authenticated_read
  ON public.diagnosis_standards FOR SELECT TO authenticated
  USING (is_active = true);

DROP POLICY IF EXISTS stg_diagnoses_authenticated_read ON public.stg_diagnoses;
CREATE POLICY stg_diagnoses_authenticated_read
  ON public.stg_diagnoses FOR SELECT TO authenticated
  USING (is_active = true);

DROP POLICY IF EXISTS diagnosis_standard_mappings_authenticated_read ON public.diagnosis_standard_mappings;
CREATE POLICY diagnosis_standard_mappings_authenticated_read
  ON public.diagnosis_standard_mappings FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS diagnosis_import_batches_admin_insert ON public.diagnosis_import_batches;
CREATE POLICY diagnosis_import_batches_admin_insert
  ON public.diagnosis_import_batches FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(),'admin'::public.app_role));

DROP POLICY IF EXISTS diagnosis_import_batches_admin_select ON public.diagnosis_import_batches;
CREATE POLICY diagnosis_import_batches_admin_select
  ON public.diagnosis_import_batches FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin'::public.app_role));

DROP POLICY IF EXISTS diagnosis_import_batches_admin_update ON public.diagnosis_import_batches;
CREATE POLICY diagnosis_import_batches_admin_update
  ON public.diagnosis_import_batches FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(),'admin'::public.app_role));

DROP POLICY IF EXISTS diagnosis_import_rows_admin_insert ON public.diagnosis_import_rows;
CREATE POLICY diagnosis_import_rows_admin_insert
  ON public.diagnosis_import_rows FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(),'admin'::public.app_role));

DROP POLICY IF EXISTS diagnosis_import_rows_admin_select ON public.diagnosis_import_rows;
CREATE POLICY diagnosis_import_rows_admin_select
  ON public.diagnosis_import_rows FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin'::public.app_role));

DROP POLICY IF EXISTS diagnosis_import_rows_admin_update ON public.diagnosis_import_rows;
CREATE POLICY diagnosis_import_rows_admin_update
  ON public.diagnosis_import_rows FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(),'admin'::public.app_role));

REVOKE ALL ON TABLE public.diagnosis_standards, public.stg_diagnoses,
  public.diagnosis_standard_mappings, public.diagnosis_import_batches,
  public.diagnosis_import_rows FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.diagnosis_standards, public.stg_diagnoses,
  public.diagnosis_standard_mappings TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.diagnosis_import_batches,
  public.diagnosis_import_rows TO authenticated;
GRANT ALL ON TABLE public.diagnosis_standards, public.stg_diagnoses,
  public.diagnosis_standard_mappings, public.diagnosis_import_batches,
  public.diagnosis_import_rows TO service_role;

-- Facility-specific terminology preference; the catalogue itself remains global.
CREATE TABLE IF NOT EXISTS public.facility_diagnosis_standards (
  facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  standard_id uuid NOT NULL REFERENCES public.diagnosis_standards(id) ON DELETE CASCADE,
  priority integer NOT NULL DEFAULT 100 CHECK (priority >= 0),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (facility_id, standard_id)
);

CREATE INDEX IF NOT EXISTS idx_facility_diagnosis_standards_priority
  ON public.facility_diagnosis_standards(facility_id, priority);

ALTER TABLE public.facility_diagnosis_standards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS facility_diagnosis_standards_authenticated_read
  ON public.facility_diagnosis_standards;
CREATE POLICY facility_diagnosis_standards_authenticated_read
  ON public.facility_diagnosis_standards FOR SELECT TO authenticated
  USING (is_active = true);

REVOKE ALL ON TABLE public.facility_diagnosis_standards FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.facility_diagnosis_standards TO authenticated;
GRANT ALL ON TABLE public.facility_diagnosis_standards TO service_role;
