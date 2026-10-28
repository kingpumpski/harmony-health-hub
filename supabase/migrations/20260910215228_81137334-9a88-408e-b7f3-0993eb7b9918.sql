-- Ensure the AI diagnosis suggestion table exists before applying its security contract.
-- The canonical generated schema exposes these columns, but the clean migration chain
-- currently reaches this hardening migration before a table-creation migration.
CREATE TABLE IF NOT EXISTS public.ai_diagnosis_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  encounter_id uuid NULL REFERENCES public.encounters(id) ON DELETE SET NULL,
  suggested_icd text NULL REFERENCES public.icd_codes(code) ON DELETE SET NULL,
  accepted boolean NULL,
  reasoning text NULL,
  model_version text NULL,
  created_at timestamptz NULL DEFAULT now()
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

-- Views must respect the querying user's permissions
ALTER VIEW public.v_patient_diagnosis_full SET (security_invoker = true);
ALTER VIEW public.v_ai_clinical_decision SET (security_invoker = true);

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
