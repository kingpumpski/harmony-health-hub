import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/20261127104000_harden_patient_audit_privacy_and_facility_access.sql', import.meta.url), 'utf8');
const databaseContract = readFileSync(new URL('../supabase/tests/database/patient_audit_access_contract.sql', import.meta.url), 'utf8');
const ui = readFileSync(new URL('../src/pages/PatientAudit.tsx', import.meta.url), 'utf8');

assert.match(migration, /REVOKE ALL PRIVILEGES ON TABLE public\.patient_audit, public\.patient_audit_log\s+FROM PUBLIC, anon, authenticated/i);
assert.match(migration, /GRANT SELECT ON TABLE public\.patient_audit_log TO authenticated/i);
assert.match(migration, /patient_audit_log_active_facility_read[\s\S]*current_user_facility_id[\s\S]*public\.patients/i);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.audit_patient_changes\(\)[\s\S]*SECURITY DEFINER[\s\S]*SET search_path = ''/i);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.audit_patient_change\(\)[\s\S]*SECURITY DEFINER[\s\S]*SET search_path = ''/i);
assert.match(migration, /old_record, new_record, changed_fields\)[\s\S]*NULL,[\s\S]*NULL,[\s\S]*changed/i);
assert.match(migration, /changed_fields, old_record, new_record\)[\s\S]*pg_catalog\.to_jsonb\(changed\),[\s\S]*NULL,[\s\S]*NULL/i);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.audit_patient_changes\(\) FROM PUBLIC, anon, authenticated/i);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.audit_patient_change\(\) FROM PUBLIC, anon, authenticated/i);
assert.doesNotMatch(migration, /\b(UPDATE|DELETE|TRUNCATE)\s+public\.patient_audit(?:_log)?\b/i, 'historical audit rows must not be rewritten or deleted');
assert.match(databaseContract, /SELECT plan\(8\)/);
assert.match(databaseContract, /patient_audit_log_active_facility_read/);
assert.match(databaseContract, /old_record, new_record/);
assert.match(ui, /from\('patient_audit_log'\)/);
assert.match(ui, /select\('id, action, changed_at, changed_by, changed_fields'\)/);
assert.doesNotMatch(ui, /old_record|new_record/);

console.log('[patient-audit-trigger-minimization] forward migration, facility boundary and snapshot minimization contracts passed');
