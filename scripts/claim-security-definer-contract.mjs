import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260929164500_harden_claim_security_definer_search_path.sql','utf8');

for (const fn of [
  'public.transition_insurance_claim_canonical',
  'public.update_insurance_claim_financials',
]) {
  if (!migration.includes(fn)) throw new Error(`Missing function: ${fn}`);
}

if (!migration.includes('set search_path = pg_catalog, public')) {
  throw new Error('Expected hardened search_path');
}

console.log('Claim SECURITY DEFINER search_path contract passed.');
