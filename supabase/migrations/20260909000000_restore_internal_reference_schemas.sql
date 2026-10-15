-- Restore internal/reference objects that the security lockdown migration protects.
-- Additive and idempotent: existing rows and existing column definitions are preserved.
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
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS action text,
  ADD COLUMN IF NOT EXISTS table_name text,
  ADD COLUMN IF NOT EXISTS record_id text,
  ADD COLUMN IF NOT EXISTS old_data jsonb,
  ADD COLUMN IF NOT EXISTS new_data jsonb,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

CREATE TABLE IF NOT EXISTS public.sync_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text,
  payload jsonb,
  synced boolean DEFAULT false
);
ALTER TABLE public.sync_queue
  ADD COLUMN IF NOT EXISTS table_name text,
  ADD COLUMN IF NOT EXISTS payload jsonb,
  ADD COLUMN IF NOT EXISTS synced boolean DEFAULT false;

CREATE TABLE IF NOT EXISTS public.ai_symptom_icd_map (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  symptom text NOT NULL,
  icd_code text REFERENCES public.icd_codes(code) ON DELETE SET NULL,
  confidence numeric,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.ai_symptom_icd_map
  ADD COLUMN IF NOT EXISTS symptom text,
  ADD COLUMN IF NOT EXISTS icd_code text REFERENCES public.icd_codes(code) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS confidence numeric,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

CREATE TABLE IF NOT EXISTS public.lab_tests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_name text,
  loinc_code text,
  specimen text,
  normal_range text,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.lab_tests
  ADD COLUMN IF NOT EXISTS test_name text,
  ADD COLUMN IF NOT EXISTS loinc_code text,
  ADD COLUMN IF NOT EXISTS specimen text,
  ADD COLUMN IF NOT EXISTS normal_range text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_ai_symptom_icd_map_icd_code
  ON public.ai_symptom_icd_map(icd_code);

-- Restore these typed diagnosis views only when missing; never replace an existing
-- deployment's view definition or disturb dependent objects.
DO $migration$
BEGIN
  IF to_regclass('public.v_patient_diagnosis_full') IS NULL THEN
    EXECUTE $view$
      CREATE VIEW public.v_patient_diagnosis_full AS
      SELECT
        d.category,
        d.diagnosis,
        d.id AS diagnosis_id,
        d.encounter_id,
        d.icd_code,
        i.description AS icd_description,
        NULL::jsonb AS medications,
        NULL::text AS recommended_action,
        NULL::text AS stg_summary
      FROM public.diagnoses d
      LEFT JOIN public.icd_codes i ON i.code = d.icd_code
    $view$;
  END IF;
  IF to_regclass('public.v_ai_clinical_decision') IS NULL THEN
    EXECUTE $view$
      CREATE VIEW public.v_ai_clinical_decision AS
      SELECT
        i.description AS description,
        d.diagnosis,
        d.encounter_id,
        d.icd_code,
        NULL::jsonb AS medications,
        NULL::text AS recommended_action
      FROM public.diagnoses d
      LEFT JOIN public.icd_codes i ON i.code = d.icd_code
    $view$;
  END IF;
END
$migration$;

ALTER VIEW public.v_patient_diagnosis_full SET (security_invoker = true);
ALTER VIEW public.v_ai_clinical_decision SET (security_invoker = true);
