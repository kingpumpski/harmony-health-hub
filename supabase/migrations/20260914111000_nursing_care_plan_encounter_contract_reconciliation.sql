-- Reconcile the nursing care-plan RPC contract with its encounter-aware insert path.
-- Additive only: existing care-plan rows remain valid and encounter_id is optional.

ALTER TABLE public.nursing_care_plans
  ADD COLUMN IF NOT EXISTS encounter_id uuid;

DO $$
BEGIN
  ALTER TABLE public.nursing_care_plans
    ADD CONSTRAINT nursing_care_plans_encounter_id_fkey
    FOREIGN KEY (encounter_id)
    REFERENCES public.encounters(id)
    ON DELETE SET NULL;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_nursing_care_plans_encounter_id
  ON public.nursing_care_plans(encounter_id);

NOTIFY pgrst, 'reload schema';
