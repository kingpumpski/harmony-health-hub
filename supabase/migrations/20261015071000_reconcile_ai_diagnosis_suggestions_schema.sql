-- Repair AI diagnosis schema drift in environments where the historical RLS migration
-- was recorded as applied while the table itself was missing or incomplete.
CREATE TABLE IF NOT EXISTS public.ai_diagnosis_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  encounter_id uuid REFERENCES public.encounters(id) ON DELETE CASCADE,
  suggested_icd text REFERENCES public.icd_codes(code) ON DELETE SET NULL,
  reasoning text,
  accepted boolean,
  model_version text,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.ai_diagnosis_suggestions
  ADD COLUMN IF NOT EXISTS encounter_id uuid REFERENCES public.encounters(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS suggested_icd text REFERENCES public.icd_codes(code) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reasoning text,
  ADD COLUMN IF NOT EXISTS accepted boolean,
  ADD COLUMN IF NOT EXISTS model_version text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_ai_diagnosis_suggestions_encounter_id
  ON public.ai_diagnosis_suggestions(encounter_id);
CREATE INDEX IF NOT EXISTS idx_ai_diagnosis_suggestions_suggested_icd
  ON public.ai_diagnosis_suggestions(suggested_icd);

ALTER TABLE public.ai_diagnosis_suggestions ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ai_diagnosis_suggestions TO authenticated;
GRANT ALL ON public.ai_diagnosis_suggestions TO service_role;
DROP POLICY IF EXISTS "clinical staff manage ai diagnosis suggestions" ON public.ai_diagnosis_suggestions;
CREATE POLICY "clinical staff manage ai diagnosis suggestions"
  ON public.ai_diagnosis_suggestions FOR ALL TO authenticated
  USING (public.is_clinical_staff(auth.uid()))
  WITH CHECK (public.is_clinical_staff(auth.uid()));

NOTIFY pgrst, 'reload schema';
