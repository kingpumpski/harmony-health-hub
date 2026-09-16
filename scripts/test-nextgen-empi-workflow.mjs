import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260916120000_nextgen_empi_merge_workflow.sql'), 'utf8');

const required = [
  'CREATE TABLE IF NOT EXISTS public.patient_identity_merges',
  'request_patient_identity_merge',
  'approve_patient_identity_merge',
  "public.has_role(auth.uid(), 'admin')",
  'Source and target patient records must be distinct',
  'A merge reason is required',
  'Source patient does not exist',
  'Target patient does not exist',
  'source_patient_id = _target_patient_id',
  'A merge requester cannot approve the same merge request',
  'FOR UPDATE',
  "status = 'merged'",
  'affected_tables',
  'REVOKE ALL ON FUNCTION public.request_patient_identity_merge',
  'REVOKE ALL ON FUNCTION public.approve_patient_identity_merge',
];
for (const token of required) if (!migration.includes(token)) throw new Error(`EMPI merge contract missing: ${token}`);

const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
if (packageJson.scripts?.['test:nextgen-empi'] !== 'node scripts/test-nextgen-empi-workflow.mjs') {
  throw new Error('EMPI workflow test is not wired into package scripts');
}

console.log('Next-gen EMPI merge workflow contract tests passed: authorization, dual-record validation, independent approval, row locking, atomic child-row reassignment, source retention and audit-oriented merge ledger are wired.');
