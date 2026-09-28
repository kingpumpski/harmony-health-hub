import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync(
  'supabase/migrations/20260928150000_harden_nursing_note_record_boundaries.sql',
  'utf8',
);

assert.ok(
  migration.includes(
    'CREATE OR REPLACE FUNCTION public.create_nursing_note',
  ),
);
assert.ok(
  migration.includes(
    "e.id = _encounter_id\n         AND e.patient_id = _patient_id",
  ),
);
assert.ok(
  migration.includes(
    "a.id = _admission_id\n         AND a.patient_id = _patient_id",
  ),
);
assert.ok(
  migration.includes(
    'A nursing note must be linked to an encounter or admission',
  ),
);
assert.ok(
  migration.includes(
    'REVOKE ALL ON FUNCTION public.create_nursing_note',
  ),
);
assert.ok(
  migration.includes(
    'GRANT EXECUTE ON FUNCTION public.create_nursing_note',
  ),
);
