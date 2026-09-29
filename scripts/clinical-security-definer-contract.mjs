import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260929171500_harden_clinical_security_definer_search_paths.sql',
  'utf8',
);

for (const fn of [
  'public.approve_lab_result',
  'public.complete_imaging_order',
  'public.confirm_pharmacy_dispense',
]) {
  if (!migration.includes(fn)) throw new Error(`Missing function: ${fn}`);
}

if (!migration.includes('set search_path = pg_catalog, public')) {
  throw new Error('Expected hardened search_path');
}

console.log('Clinical SECURITY DEFINER search_path contract passed.');
