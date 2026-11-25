-- Restore the nullable ward relationship expected by the canonical
-- nursing-handover RPC. The live RPC already validates that a supplied ward
-- belongs to the patient's active facility before inserting the handover.
--
-- The canonical live schema lacks this column, while later recorded handover
-- RPC migrations continue to reference it. The original baseline SQL is not
-- available to prove exactly where the omission occurred. This repair restores
-- the intended FK without rewriting historical migrations or the RPC.

BEGIN;

ALTER TABLE public.nursing_shift_handovers
  ADD COLUMN IF NOT EXISTS ward_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.nursing_shift_handovers'::regclass
      AND conname = 'nursing_shift_handovers_ward_id_fkey'
  ) THEN
    ALTER TABLE public.nursing_shift_handovers
      ADD CONSTRAINT nursing_shift_handovers_ward_id_fkey
      FOREIGN KEY (ward_id)
      REFERENCES public.ward_units(id)
      ON DELETE SET NULL;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_nursing_shift_handovers_ward_id
  ON public.nursing_shift_handovers(ward_id);

COMMENT ON COLUMN public.nursing_shift_handovers.ward_id IS
  'Optional ward association; the handover RPC enforces that the ward belongs to the patient facility.';

COMMIT;
