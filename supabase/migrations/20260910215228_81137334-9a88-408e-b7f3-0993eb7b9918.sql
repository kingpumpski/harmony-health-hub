-- Restore canonical reference/internal schemas before this migration applies
-- grants, indexes, RLS, or policies to them. Definitions follow generated
-- Supabase database types and downstream FK/index contracts.
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  action text,
  table_name text,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz default now()
);

create table if not exists public.sync_queue (
  id uuid primary key default gen_random_uuid(),
  payload jsonb,
  synced boolean default false,
  table_name text
);

create table if not exists public.lab_tests (
  id uuid primary key default gen_random_uuid(),
  loinc_code text,
  normal_range text,
  specimen text,
  test_name text,
  created_at timestamptz default now()
);

create table if not exists public.ai_symptom_icd_map (
  id uuid primary key default gen_random_uuid(),
  confidence numeric,
  created_at timestamptz default now(),
  icd_code text references public.icd_codes(code),
  symptom text not null
);

create table if not exists public.ai_diagnosis_suggestions (
  id uuid primary key default gen_random_uuid(),
  encounter_id uuid references public.encounters(id),
  suggested_icd text references public.icd_codes(code),
  reasoning text,
  model_version text,
  accepted boolean default false,
  created_at timestamptz default now()
);

-- Lock down reference/internal tables
ALTER TABLE public.ai_diagnosis_suggestions ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ai_diagnosis_suggestions TO authenticated;
GRANT ALL ON public.ai_diagnosis_suggestions TO service_role;
CREATE POLICY "clinical staff manage ai diagnosis suggestions"
  ON public.ai_diagnosis_suggestions FOR ALL TO authenticated
  USING (public.is_clinical_staff(auth.uid()))
  WITH CHECK (public.is_clinical_staff(auth.uid()));

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.audit_logs TO authenticated;
GRANT ALL ON public.audit_logs TO service_role;
CREATE POLICY "admins read audit logs"
  ON public.audit_logs FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

ALTER TABLE public.sync_queue ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public.sync_queue TO service_role;
GRANT SELECT ON public.sync_queue TO authenticated;
CREATE POLICY "admins read sync queue"
  ON public.sync_queue FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

ALTER TABLE public.ai_symptom_icd_map ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.ai_symptom_icd_map TO authenticated;
GRANT ALL ON public.ai_symptom_icd_map TO service_role;
CREATE POLICY "staff read symptom map"
  ON public.ai_symptom_icd_map FOR SELECT TO authenticated
  USING (public.is_clinical_staff(auth.uid()));
CREATE POLICY "admins write symptom map"
  ON public.ai_symptom_icd_map FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

ALTER TABLE public.lab_tests ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.lab_tests TO authenticated;
GRANT ALL ON public.lab_tests TO service_role;
CREATE POLICY "staff read lab tests"
  ON public.lab_tests FOR SELECT TO authenticated
  USING (public.is_clinical_staff(auth.uid()));
CREATE POLICY "admins write lab tests"
  ON public.lab_tests FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Optional legacy views must respect the querying user's permissions when
-- present. These views are not created by the current migration history, so
-- guard by catalog kind instead of making clean replay depend on them.
DO $
DECLARE
  v_name text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY['v_patient_diagnosis_full','v_ai_clinical_decision'] LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = v_name AND c.relkind = 'v'
    ) THEN
      EXECUTE format('ALTER VIEW public.%I SET (security_invoker = true)', v_name);
    END IF;
  END LOOP;
END;
$;

-- Tighten patient document storage access
DROP POLICY IF EXISTS "outside_lab_read" ON storage.objects;
CREATE POLICY "outside_lab_read" ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'outside-lab'
    AND (public.is_clinical_staff(auth.uid()) OR auth.uid()::text = (storage.foldername(name))[1])
  );

DROP POLICY IF EXISTS "outside_lab_upload" ON storage.objects;
CREATE POLICY "outside_lab_upload" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'outside-lab'
    AND (public.is_clinical_staff(auth.uid()) OR auth.uid()::text = (storage.foldername(name))[1])
  );