-- Create the AI diagnosis suggestion relation before the RLS/grant migration
-- 20260910215228_81137334-9a88-408e-b7f3-0993eb7b9918.sql references it.
-- Columns and nullability follow src/integrations/supabase/types.ts.
CREATE TABLE public.ai_diagnosis_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  encounter_id uuid REFERENCES public.encounters(id) ON DELETE SET NULL,
  suggested_icd text REFERENCES public.icd_codes(code) ON DELETE SET NULL,
  accepted boolean,
  reasoning text,
  model_version text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fk_ai_diagnosis_suggestions_encounter_id
  ON public.ai_diagnosis_suggestions (encounter_id);

CREATE INDEX IF NOT EXISTS idx_fk_ai_diagnosis_suggestions_suggested_icd
  ON public.ai_diagnosis_suggestions (suggested_icd);
