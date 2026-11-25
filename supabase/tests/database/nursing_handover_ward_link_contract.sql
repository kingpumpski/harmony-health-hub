BEGIN;

SELECT plan(4);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'nursing_shift_handovers'
      AND column_name = 'ward_id'
      AND is_nullable = 'YES'
      AND data_type = 'uuid'
  ),
  'nursing handovers retain an optional UUID ward association'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint c
    WHERE c.conrelid = 'public.nursing_shift_handovers'::regclass
      AND c.confrelid = 'public.ward_units'::regclass
      AND c.contype = 'f'
      AND c.conname = 'nursing_shift_handovers_ward_id_fkey'
      AND c.convalidated
      AND cardinality(c.conkey) = 1
      AND c.conkey = ARRAY[
        (SELECT attnum FROM pg_attribute
         WHERE attrelid = 'public.nursing_shift_handovers'::regclass
           AND attname = 'ward_id')
      ]::smallint[]
      AND c.confkey = ARRAY[
        (SELECT attnum FROM pg_attribute
         WHERE attrelid = 'public.ward_units'::regclass
           AND attname = 'id')
      ]::smallint[]
  ),
  'nursing handover ward_id references canonical ward_units.id'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.nursing_shift_handovers'::regclass
      AND conname = 'nursing_shift_handovers_ward_id_fkey'
      AND confdeltype = 'n'
  ),
  'deleting a ward preserves the handover and clears its optional ward link'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class t ON t.oid = i.indrelid
    JOIN pg_class x ON x.oid = i.indexrelid
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(i.indkey)
    WHERE t.oid = 'public.nursing_shift_handovers'::regclass
      AND x.relname = 'idx_nursing_shift_handovers_ward_id'
      AND i.indisvalid
      AND i.indisready
      AND a.attname = 'ward_id'
      AND i.indnatts = 1
  ),
  'nursing handover ward_id has a valid supporting index'
);

SELECT * FROM finish();
ROLLBACK;
