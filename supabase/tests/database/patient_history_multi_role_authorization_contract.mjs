import fs from 'node:fs';

const source = fs.readFileSync('supabase/migrations/20260921120000_post_merge_runtime_patient_history_rpcs.sql', 'utf8');

if (source.includes('SELECT ur.role::text INTO v_role')) {
  throw new Error('patient history authorization still depends on the first assigned role');
}
if (source.includes('IF v_role NOT IN')) {
  throw new Error('patient history authorization still uses a single resolved role');
}

const required = [
  "CREATE OR REPLACE FUNCTION public.get_patient_appointments(_patient_id uuid, _limit integer DEFAULT 100)",
  "CREATE OR REPLACE FUNCTION public.get_patient_invoices(_patient_id uuid, _limit integer DEFAULT 100)",
  "public.has_role(auth.uid(),'admin')",
  "public.has_role(auth.uid(),'practitioner')",
  "public.has_role(auth.uid(),'nurse')",
  "public.has_role(auth.uid(),'midwife')",
  "public.has_role(auth.uid(),'specialist_nurse')",
  "public.has_role(auth.uid(),'front_desk')",
  "public.has_role(auth.uid(),'accountant')"
];

for (const marker of required) {
  if (!source.includes(marker)) throw new Error('patient history multi-role contract missing: ' + marker);
}

console.log('Patient history multi-role authorization contract passed');
