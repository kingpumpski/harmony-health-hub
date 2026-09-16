import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260916180000_nextgen_claims_adjudication_concurrency.sql', 'utf8');
const clinicalAudit = fs.readFileSync('supabase/migrations/20260916103000_nextgen_clinical_audit_convergence.sql', 'utf8');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));

const required = [
  'CREATE OR REPLACE FUNCTION public.transition_insurance_claim',
  'CREATE OR REPLACE FUNCTION public.update_insurance_claim_financials',
  'SECURITY DEFINER',
  'FOR UPDATE',
  "c.status IN ('paid','voided')",
  'idempotent',
  "WHEN 'submitted'",
  "WHEN 'under_review'",
  "WHEN 'approved'",
  "WHEN 'partially_approved'",
  "WHEN 'rejected'",
  "WHEN 'resubmission_required'",
  'Invalid claim transition',
  'Approved amount exceeds claimed amount',
  'Paid amount exceeds approved amount',
  'Approved amount is required for an adjudication decision',
  'Paid amount is required before marking a claim paid',
  'Rejection reason is required',
  'insurance_claim_events',
  'status_changed',
  'financials_updated',
  'REVOKE ALL ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT) FROM PUBLIC, anon',
  'REVOKE ALL ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) FROM PUBLIC, anon',
  'GRANT EXECUTE ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated',
];

for (const token of required) {
  if (!migration.includes(token)) throw new Error(`Claims adjudication control missing: ${token}`);
}

if (!clinicalAudit.includes("'insurance_claims'")) throw new Error('Canonical clinical audit convergence does not include insurance claims');
if (pkg.scripts?.['test:nextgen-claims-adjudication'] !== 'node scripts/test-nextgen-claims-adjudication.mjs') {
  throw new Error('Claims adjudication test is not wired into package scripts');
}

console.log('Next-gen claims adjudication contract verification passed: row locking, terminal-state protection, monotonic transitions, financial bounds, required adjudication/rejection evidence, canonical claim events, execute isolation, and audit convergence are present.');
