import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync(
  'supabase/migrations/20260923160000_legacy_clinical_context_hardening.sql',
  'utf8',
);

assert.match(migration, /get_patient_hub_snapshot\(_patient_id UUID\)/);
assert.match(migration, /'gender',p\.gender/);
assert.doesNotMatch(migration, /'sex',p\.sex/);
assert.doesNotMatch(migration, /WHEN is_clinical THEN to_jsonb\(p\)/);
assert.match(migration, /ghana_card_number/);
assert.match(migration, /insurance_number/);

assert.match(
  migration,
  /create_ophthalmology_exam[\s\S]*COALESCE\(status,'active'\) <> 'inactive'/,
);
assert.match(
  migration,
  /create_walk_in_billable_service[\s\S]*auth\.uid\(\) IS NULL/,
);
assert.match(
  migration,
  /create_walk_in_billable_service[\s\S]*COALESCE\(status,'active'\) <> 'inactive'/,
);
assert.match(
  migration,
  /create_walk_in_billable_service[\s\S]*NULLIF\(btrim\(_service_code\),' '\) IS NULL|NULLIF\(btrim\(_service_code\),''\) IS NULL/,
);

for (const fn of [
  'get_patient_hub_snapshot(UUID)',
  'create_ophthalmology_exam(UUID,TEXT,TEXT,TEXT,NUMERIC,TEXT,TEXT)',
  'create_walk_in_billable_service(UUID,TEXT,NUMERIC,TEXT)',
]) {
  assert.match(
    migration,
    new RegExp('REVOKE ALL ON FUNCTION public\\.' + fn.replace(/[()]/g, '\\$&') + ' FROM PUBLIC,anon'),
  );
}

console.log('Legacy clinical context hardening contract passed.');
