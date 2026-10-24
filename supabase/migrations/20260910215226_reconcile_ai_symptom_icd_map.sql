-- Restore the canonical symptom-to-ICD reference table before historical
-- RLS and foreign-key-index migrations reference it on clean installations.
-- Existing installations retain their rows; missing canonical columns are added.
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
  ADD COLUMN IF NOT EXISTS icd_code text,
  ADD COLUMN IF NOT EXISTS confidence numeric,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

DO $reconcile_ai_symptom_icd_map$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.ai_symptom_icd_map'::regclass
      AND conname = 'ai_symptom_icd_map_icd_code_fkey'
  ) THEN
    ALTER TABLE public.ai_symptom_icd_map
      ADD CONSTRAINT ai_symptom_icd_map_icd_code_fkey
      FOREIGN KEY (icd_code) REFERENCES public.icd_codes(code) ON DELETE SET NULL;
  END IF;
END;
$reconcile_ai_symptom_icd_map$;
