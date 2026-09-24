import fs from 'node:fs';
import assert from 'node:assert/strict';

const s = fs.readFileSync(
  'supabase/migrations/20260923163000_clinical_continuity_execute_hardening.sql',
  'utf8',
);

assert.match(
  s,
  /REVOKE ALL ON FUNCTION public\.get_patient_care_continuity\(UUID\) FROM PUBLIC, anon/,
);
assert.match(
  s,
  /GRANT EXECUTE ON FUNCTION public\.get_patient_care_continuity\(UUID\) TO authenticated/,
);

console.log('Clinical continuity execute hardening contract passed.');
