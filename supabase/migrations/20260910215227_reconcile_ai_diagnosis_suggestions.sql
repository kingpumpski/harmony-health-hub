-- Restore the canonical AI diagnosis suggestion table before historical
-- hardening/index migrations reference it. Additive and safe for existing installs.
CREATE TABLE IF NOT EXISTS public.ai_diagnosis_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  encounter_id uuid REFERENCES public.encounters(id) ON DELETE SET NULL,
  suggested_icd text REFERENCES public.icd_codes(code) ON DELETE SET NULL,
  reasoning text,
  accepted boolean,
  model_version text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_diagnosis_suggestions_encounter_id
  ON public.ai_diagnosis_suggestions(encounter_id);
CREATE INDEX IF NOT EXISTS idx_ai_diagnosis_suggestions_suggested_icd
  ON public.ai_diagnosis_suggestions(suggested_icd);
