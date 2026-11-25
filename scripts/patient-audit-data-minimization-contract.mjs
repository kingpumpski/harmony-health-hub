import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/PatientAudit.tsx', import.meta.url), 'utf8');

assert.match(source, /select\('id, action, changed_at, changed_by, changed_fields'\)/, 'audit screen must request metadata and changed-field names only');
assert.doesNotMatch(source, /old_record|new_record/, 'audit screen must not fetch or render full patient snapshots');
assert.doesNotMatch(source, /JSON[.]stringify\(row[.](old_record|new_record)/, 'audit screen must not serialize patient snapshots into the UI');
assert.match(source, /changed_fields/, 'audit screen must retain a useful change summary');

console.log('[patient-audit-data-minimization] source contract passed');
