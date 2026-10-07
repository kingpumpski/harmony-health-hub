import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readdirSync('supabase/migrations').find((name) => name.includes('patient_portal_identity_index'));
assert.ok(migration, 'Patient portal identity index migration is missing');
const sql = fs.readFileSync('supabase/migrations/' + migration, 'utf8').toLowerCase();
assert.match(sql, /on\s+public\.patients\s*\(\s*lower\(email\)\s*\)/);
assert.match(sql, /where\s+coalesce\(status\s*,\s*'active'\)\s*<>\s*'inactive'/);
console.log('Patient portal identity index contract passed.');
