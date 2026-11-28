import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migrationPath = 'supabase/migrations/20261127100200_restore_nursing_handover_ward_link.sql';
const migration = readFileSync(migrationPath, 'utf8');
const ledger = JSON.parse(readFileSync('supabase/migration-ledger-baseline.json', 'utf8'));
const rpcMigration = readFileSync(
  'supabase/migrations/20261004225000_harden_care_transition_handover_lab_approval.sql',
  'utf8',
);
const ui = readFileSync('src/pages/NursingHandover.tsx', 'utf8');

const migrationFileName = migrationPath.split('/').at(-1) ?? migrationPath;
const version = /^([0-9]{14})_/.exec(migrationFileName)?.[1];
assert.ok(version, 'forward migration must use a 14-digit timestamp');
assert.ok(version > ledger.latest_version, 'forward migration must sort after the verified hosted ledger');

assert.match(migration, /ALTER TABLE public\.nursing_shift_handovers\s+ADD COLUMN IF NOT EXISTS ward_id uuid/i);
assert.match(
  migration,
  /FOREIGN KEY\s*\(ward_id\)\s*REFERENCES public\.ward_units\s*\(id\)\s*ON DELETE SET NULL/i,
  'ward association must retain the nullable ward_units relationship',
);
assert.match(
  migration,
  /CREATE INDEX idx_nursing_shift_handovers_ward_id\s+ON public\.nursing_shift_handovers\s*\(ward_id\)/i,
  'ward FK must have a supporting index',
);
assert.match(migration, /COMMENT ON COLUMN public\.nursing_shift_handovers\.ward_id/i);
assert.match(
  migration,
  /Existing nursing_shift_handovers_ward_id_fkey conflicts with the canonical ward link/i,
  'an incorrect same-name FK must stop the migration',
);
assert.match(
  migration,
  /Existing idx_nursing_shift_handovers_ward_id conflicts with the canonical ward_id index/i,
  'an incorrect same-name index must stop the migration',
);
assert.match(
  migration,
  /v_index\.indkey::smallint\[\] <> ARRAY\[v_ward_attnum\]::smallint\[\]/i,
  'index validation must compare the exact single-column definition',
);
const databaseContract = readFileSync(
  'supabase/tests/database/nursing_handover_ward_link_contract.sql',
  'utf8',
);
assert.match(databaseContract, /SELECT plan\(4\)/);
assert.match(databaseContract, /confdeltype = 'n'/);

assert.doesNotMatch(migration, /\b(DROP|TRUNCATE)\s+(TABLE|COLUMN|CONSTRAINT|INDEX)\b/i);
assert.doesNotMatch(migration, /CREATE OR REPLACE FUNCTION/i, 'repair must preserve the already-deployed facility-aware RPC');

assert.match(
  rpcMigration,
  /IF _ward_id IS NOT NULL AND NOT EXISTS\s*\(SELECT 1 FROM public\.ward_units WHERE id=_ward_id AND facility_id=pf\)/i,
  'existing RPC must enforce same-facility ward selection',
);
assert.match(
  rpcMigration,
  /INSERT INTO public\.nursing_shift_handovers\s*\(patient_id,facility_id,ward_id,/i,
  'existing RPC must persist the optional ward association',
);
assert.match(
  ui,
  /supabase\.rpc\('create_nursing_shift_handover'/,
  'handover UI must continue using the controlled RPC',
);
assert.doesNotMatch(
  ui.match(/supabase\.rpc\('create_nursing_shift_handover',[\s\S]*?\}\);/)?.[0] ?? '',
  /_ward_id\s*:/,
  'current UI may omit optional ward and rely on the nullable RPC default',
);

console.log('Nursing handover ward-link migration contract passed.');
