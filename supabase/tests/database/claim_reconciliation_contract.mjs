import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20260929120000_claim_invoice_reconciliation.sql', 'utf8')
  + '\n'
  + fs.readFileSync('supabase/migrations/20260929121500_claim_reconciliation_read_context.sql', 'utf8');

const required = [
  'CREATE OR REPLACE FUNCTION public.reconcile_insurance_claim_to_invoice',
  "NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant'))",
  "IF c.status IN ('paid','voided')",
  'Claim invoice does not belong to claim patient',
  "SET search_path TO 'pg_catalog','public'",
  'REVOKE ALL ON FUNCTION public.reconcile_insurance_claim_to_invoice(uuid) FROM PUBLIC,anon',
  'GRANT EXECUTE ON FUNCTION public.reconcile_insurance_claim_to_invoice(uuid) TO authenticated',
  'CREATE OR REPLACE FUNCTION public.get_insurance_claim_reconciliation_context',
  'REVOKE ALL ON FUNCTION public.get_insurance_claim_reconciliation_context(uuid[]) FROM PUBLIC,anon',
  'GRANT EXECUTE ON FUNCTION public.get_insurance_claim_reconciliation_context(uuid[]) TO authenticated',
  'insurance_company_id',
  'invoice_insurance_total',
];

const missing = required.filter((item) => !sql.includes(item));
if (missing.length) {
  console.error('Claim reconciliation contract failed:', missing);
  process.exitCode = 1;
} else {
  console.log('Claim reconciliation contract: all invariants present');
}
