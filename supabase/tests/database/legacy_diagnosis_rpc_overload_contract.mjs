import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260923200000_remove_legacy_add_encounter_diagnosis_overload.sql',
  'utf8',
);

assert.match(
  migration,
  /DROP FUNCTION IF EXISTS public\.add_encounter_diagnosis\(uuid,\s*text\)\s*;/i,
);

console.log('legacy add_encounter_diagnosis overload retirement contract passed');
