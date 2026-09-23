import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260923210000_tighten_insurance_case_mutation_authority.sql',
  'utf8',
);

assert.match(migration,/public\.has_role\(auth\.uid\(\),'admin'\)/i);
assert.match(migration,/public\.has_role\(auth\.uid\(\),'accountant'\)/i);
assert.doesNotMatch(migration,/public\.has_role\(auth\.uid\(\),'front_desk'\)/i);
assert.match(migration,/REVOKE ALL ON FUNCTION public\.update_insurance_case/i);
assert.match(migration,/GRANT EXECUTE ON FUNCTION public\.update_insurance_case/i);

console.log('insurance-case mutation authority contract passed');
