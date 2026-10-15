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
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
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
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
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
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
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
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
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
        i.category,
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

-- Apply the lockdown as part of the late repair too, because these objects may
-- be created on installations where the earlier security migration is already recorded.
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.audit_logs TO authenticated;
GRANT ALL ON public.audit_logs TO service_role;
DROP POLICY IF EXISTS "admins read audit logs" ON public.audit_logs;
CREATE POLICY "admins read audit logs" ON public.audit_logs
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

ALTER TABLE public.sync_queue ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public.sync_queue TO service_role;
DROP POLICY IF EXISTS "admins read sync queue" ON public.sync_queue;
CREATE POLICY "admins read sync queue" ON public.sync_queue
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

ALTER TABLE public.ai_symptom_icd_map ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.ai_symptom_icd_map TO authenticated;
GRANT ALL ON public.ai_symptom_icd_map TO service_role;
DROP POLICY IF EXISTS "staff read symptom map" ON public.ai_symptom_icd_map;
DROP POLICY IF EXISTS "admins write symptom map" ON public.ai_symptom_icd_map;
DROP POLICY IF EXISTS staff_read_symptom_map ON public.ai_symptom_icd_map;
DROP POLICY IF EXISTS admins_write_symptom_map ON public.ai_symptom_icd_map;
CREATE POLICY "staff read symptom map" ON public.ai_symptom_icd_map
  FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()));
CREATE POLICY "admins write symptom map" ON public.ai_symptom_icd_map
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

ALTER TABLE public.lab_tests ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.lab_tests TO authenticated;
GRANT ALL ON public.lab_tests TO service_role;
DROP POLICY IF EXISTS "staff read lab tests" ON public.lab_tests;
DROP POLICY IF EXISTS "admins write lab tests" ON public.lab_tests;
CREATE POLICY "staff read lab tests" ON public.lab_tests
  FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()));
CREATE POLICY "admins write lab tests" ON public.lab_tests
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

NOTIFY pgrst, 'reload schema';
