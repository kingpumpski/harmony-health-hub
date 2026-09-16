import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const audit = read('supabase/migrations/20260916103000_nextgen_clinical_audit_convergence.sql');
const auditFoundation = read('supabase/migrations/20260912162000_clinical_change_audit_hardening.sql');
const labWorkflow = read('supabase/migrations/20260912203000_clinical_module_workflow_security.sql');
const imagingWorkflow = read('supabase/migrations/20260914130000_imaging_lifecycle_server_authority.sql');
const claimsHardening = read('supabase/migrations/20260914150000_clinical_claim_nursing_direct_mutation_hardening.sql');
const claimsWorkflow = read('supabase/migrations/20260912035000_global_hims_operational_integrity.sql');
const mutationLockdown = read('supabase/migrations/20260914140000_clinical_direct_mutation_surface_hardening.sql');
const appointmentLockdown = read('supabase/migrations/20260914143000_appointment_direct_write_lockdown.sql');
const appointmentWorkflow = read('supabase/migrations/20260913213000_operational_rpc_contract_reconciliation.sql');
const medicationWorkflow = read('supabase/migrations/20260912032000_global_hims_secure_workflows.sql');
const offlineSync = read('src/lib/offlineSync.ts');

for (const table of ['patients', 'appointments', 'encounters', 'prescriptions', 'medication_administrations', 'lab_orders', 'lab_results', 'imaging_orders', 'insurance_claims', 'invoices', 'payments']) {
  if (!audit.includes(`'${table}'`)) throw new Error(`Clinical audit convergence missing ${table}`);
}
if (!audit.includes('audit_clinical_record_change')) throw new Error('Clinical audit convergence is not using the canonical audit trigger');
if (!auditFoundation.includes('CREATE OR REPLACE FUNCTION public.audit_clinical_record_change()')) throw new Error('Canonical clinical audit function missing');

for (const token of ['collect_lab_sample', 'enter_lab_result', 'approve_lab_result', 'REVOKE INSERT, UPDATE, DELETE ON public.lab_results FROM authenticated']) {
  if (!labWorkflow.includes(token)) throw new Error(`Laboratory server boundary missing: ${token}`);
}
for (const token of ['start_imaging_order', 'complete_imaging_order', 'REVOKE UPDATE, DELETE ON TABLE public.imaging_orders FROM authenticated']) {
  if (!imagingWorkflow.includes(token)) throw new Error(`Imaging server boundary missing: ${token}`);
}
for (const token of ['REVOKE INSERT, UPDATE, DELETE ON TABLE public.insurance_claims FROM authenticated']) {
  if (!claimsHardening.includes(token)) throw new Error(`Claims direct-write lockdown missing: ${token}`);
}
for (const token of ['update_insurance_claim_financials', 'FOR UPDATE', 'Closed claim cannot be edited', 'Invalid paid amount']) {
  if (!claimsWorkflow.includes(token)) throw new Error(`Claims financial integrity boundary missing: ${token}`);
}
for (const token of ['REVOKE INSERT, UPDATE, DELETE ON TABLE public.lab_results FROM authenticated', 'REVOKE INSERT ON TABLE public.imaging_orders FROM authenticated', 'REVOKE INSERT, UPDATE, DELETE ON TABLE public.prescriptions FROM authenticated']) {
  if (!mutationLockdown.includes(token)) throw new Error(`Clinical direct-mutation lockdown missing: ${token}`);
}
for (const token of ['REVOKE INSERT, UPDATE, DELETE ON public.appointments FROM authenticated', 'REVOKE ALL ON FUNCTION public.claim_appointment(uuid) FROM PUBLIC, anon', 'GRANT EXECUTE ON FUNCTION public.claim_appointment(uuid) TO authenticated']) {
  if (!appointmentLockdown.includes(token)) throw new Error(`Appointment mutation boundary missing: ${token}`);
}
for (const token of ['claim_appointment', 'Closed appointments cannot start a new encounter']) {
  if (!appointmentWorkflow.includes(token)) throw new Error(`Appointment workflow concurrency/closure boundary missing: ${token}`);
}
for (const token of ["IF v.status IN ('cancelled','administered','refused','omitted') THEN RAISE EXCEPTION 'Medication record is already closed'", 'record_system_audit']) {
  if (!medicationWorkflow.includes(token)) throw new Error(`Medication administration safety boundary missing: ${token}`);
}

// Offline authentication failures are retryable. A stale access token must never
// permanently strand queued clinical work; replay obtains a fresh token from the
// registered auth provider. Authorization failures (403), validation/conflict
// failures and not-found responses remain blocked for human review.
if (!offlineSync.includes('const isTransientFailure =') && !offlineSync.includes('function isTransientFailure')) throw new Error('Offline retry classification helper missing');
if (!offlineSync.includes('status === 401')) throw new Error('Offline 401 authentication recovery is not retryable');
if (!offlineSync.includes('status === 403')) throw new Error('Offline 403 authorization failure is not distinguished from authentication');
if (!offlineSync.includes('authHeaderProvider')) throw new Error('Offline replay is missing the server-session token provider boundary');

console.log('Next-gen clinical workflow boundary tests passed: audit convergence, appointment authority/concurrency, medication safety, laboratory finalisation, imaging lifecycle, claims integrity, direct-write lockdowns, and offline authentication recovery are contractually wired.');
