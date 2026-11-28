import fs from 'node:fs';
import path from 'node:path';
import { inspectMigrationDirectory, migrationInventoryErrors } from './migration-inventory.mjs';

const errors = migrationInventoryErrors(inspectMigrationDirectory(path.join(process.cwd(), 'supabase/migrations')));
// These existing contracts cover the known operational drift and its access boundaries.
for (const file of [
  'supabase/tests/database/operational_read_schema_contract.sql',
  'supabase/tests/database/laboratory_missing_objects_contract.sql',
  'supabase/tests/database/hr_payroll_record_management_contract.sql',
  'supabase/tests/database/security_access_contract.sql',
  'supabase/tests/database/security_definer_auth_contract.sql',
  'supabase/tests/database/laboratory_panel_access_contract.sql',
  'supabase/tests/database/patient_audit_access_contract.sql',
]) {
  if (!fs.existsSync(file) || !fs.readFileSync(file, 'utf8').trim()) errors.push(`Required database contract missing or empty: ${file}`);
}
for (const script of [
  'scripts/migration-ledger-source-reconciliation-contract.mjs',
  'scripts/patient-audit-trigger-minimization-contract.mjs',
  'scripts/security-definer-auth-contract-source.mjs',
]) {
  if (!fs.existsSync(script) || !fs.readFileSync(script, 'utf8').trim()) {
    errors.push(`Required migration/security contract script missing or empty: ${script}`);
  }
}
for (const workflow of ['migration-contract.yml', 'supabase-migrations.yml']) {
  const source = fs.readFileSync(path.join('.github/workflows', workflow), 'utf8');
  for (const match of source.matchAll(/\bnode\s+((?:scripts|supabase\/tests)\/[^\s"']+\.mjs)/g)) {
    if (!fs.existsSync(match[1])) errors.push(`${workflow} references missing script ${match[1]}`);
  }
}
for (const error of errors) console.error(`[migration-contract] ${error}`);
if (errors.length) process.exitCode = 1;
else console.log('[migration-contract] migration identities and required contract assets passed; runtime schema parity requires clean replay and live database tests');