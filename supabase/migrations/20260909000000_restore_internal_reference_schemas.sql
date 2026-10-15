-- Restore internal/reference objects that the security lockdown migration protects.
-- These definitions are additive and intentionally preserve existing rows.
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

CREATE TABLE IF NOT EXISTS public.sync_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text,
  payload jsonb,
  synced boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.ai_symptom_icd_map (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  symptom text NOT NULL,
  icd_code text REFERENCES public.icd_codes(code) ON DELETE SET NULL,
  confidence numeric,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.lab_tests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_name text,
  loinc_code text,
  specimen text,
  normal_range text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_symptom_icd_map_icd_code
  ON public.ai_symptom_icd_map(icd_code);

-- Recreate the typed diagnosis views if they were omitted from an older migration chain.
CREATE OR REPLACE VIEW public.v_patient_diagnosis_full AS
SELECT
  d.id AS diagnosis_id,
  d.encounter_id,
  d.diagnosis,
  d.icd_code,
  i.description AS icd_description,
  i.category,
  NULL::jsonb AS medications,
  NULL::text AS recommended_action,
  NULL::text AS stg_summary
FROM public.diagnoses d
LEFT JOIN public.icd_codes i ON i.code = d.icd_code;

CREATE OR REPLACE VIEW public.v_ai_clinical_decision AS
SELECT
  d.encounter_id,
  d.diagnosis,
  d.icd_code,
  i.description AS description,
  NULL::jsonb AS medications,
  NULL::text AS recommended_action
FROM public.diagnoses d
LEFT JOIN public.icd_codes i ON i.code = d.icd_code;

ALTER VIEW public.v_patient_diagnosis_full SET (security_invoker = true);
ALTER VIEW public.v_ai_clinical_decision SET (security_invoker = true);
