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

for (const table of ['appointments', 'medication_administrations', 'lab_orders', 'lab_results', 'imaging_orders', 'insurance_claims']) {
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

console.log('Next-gen clinical workflow boundary tests passed: audit convergence, laboratory finalisation, imaging lifecycle, claims integrity, and direct-write lockdowns are contractually wired.');
