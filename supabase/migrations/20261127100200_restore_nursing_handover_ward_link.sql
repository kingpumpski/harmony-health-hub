-- Restore the nullable ward relationship expected by the canonical
-- nursing-handover RPC. The live RPC already validates that a supplied ward
-- belongs to the patient's active facility before inserting the handover.
--
-- The canonical live schema lacks this column, while later recorded handover
-- RPC migrations continue to reference it. The original baseline SQL is not
-- available to prove exactly where the omission occurred. This repair restores
-- the intended FK without rewriting historical migrations or the RPC.
--
-- Existing objects with the canonical names are validated rather than silently
-- accepted. A conflicting object must be reconciled explicitly before apply.

BEGIN;

ALTER TABLE public.nursing_shift_handovers
  ADD COLUMN IF NOT EXISTS ward_id uuid;

DO $$
DECLARE
  v_constraint record;
BEGIN
  SELECT c.contype, c.confrelid, c.convalidated, c.confdeltype,
         c.conkey, c.confkey
    INTO v_constraint
  FROM pg_constraint c
  WHERE c.conrelid = 'public.nursing_shift_handovers'::regclass
    AND c.conname = 'nursing_shift_handovers_ward_id_fkey';

  IF NOT FOUND THEN
    ALTER TABLE public.nursing_shift_handovers
      ADD CONSTRAINT nursing_shift_handovers_ward_id_fkey
      FOREIGN KEY (ward_id)
      REFERENCES public.ward_units(id)
      ON DELETE SET NULL;
  ELSE
    IF v_constraint.contype <> 'f'
       OR v_constraint.confrelid <> 'public.ward_units'::regclass
       OR NOT v_constraint.convalidated
       OR v_constraint.confdeltype <> 'n'
       OR v_constraint.conkey <> ARRAY[
         (SELECT attnum FROM pg_attribute
          WHERE attrelid = 'public.nursing_shift_handovers'::regclass
            AND attname = 'ward_id')
       ]::smallint[]
       OR v_constraint.confkey <> ARRAY[
         (SELECT attnum FROM pg_attribute
          WHERE attrelid = 'public.ward_units'::regclass
            AND attname = 'id')
       ]::smallint[] THEN
      RAISE EXCEPTION
        'Existing nursing_shift_handovers_ward_id_fkey conflicts with the canonical ward link; reconcile it before applying this migration';
    END IF;
  END IF;
END;
$$;

DO $$
DECLARE
  v_index record;
  v_ward_attnum smallint;
BEGIN
  SELECT attnum INTO v_ward_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.nursing_shift_handovers'::regclass
    AND attname = 'ward_id'
    AND NOT attisdropped;

  SELECT i.indisvalid, i.indisready, i.indnatts, i.indkey
    INTO v_index
  FROM pg_index i
  JOIN pg_class x ON x.oid = i.indexrelid
  WHERE i.indrelid = 'public.nursing_shift_handovers'::regclass
    AND x.relname = 'idx_nursing_shift_handovers_ward_id';

  IF FOUND THEN
    IF NOT v_index.indisvalid
       OR NOT v_index.indisready
       OR v_index.indnatts <> 1
       OR v_index.indkey::smallint[] <> ARRAY[v_ward_attnum]::smallint[] THEN
      RAISE EXCEPTION
        'Existing idx_nursing_shift_handovers_ward_id conflicts with the canonical ward_id index; reconcile it before applying this migration';
    END IF;
  ELSE
    CREATE INDEX idx_nursing_shift_handovers_ward_id
      ON public.nursing_shift_handovers(ward_id);
  END IF;
END;
$$;

COMMENT ON COLUMN public.nursing_shift_handovers.ward_id IS
  'Optional ward association; the handover RPC enforces that the ward belongs to the patient facility.';

COMMIT;
