import fs from 'node:fs';

const source = fs.readFileSync('supabase/migrations/20260921121000_post_merge_runtime_role_lookup_fix.sql', 'utf8');

if (source.includes("SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;")) {
  throw new Error('operational workspace authorization still depends on the first assigned role');
}
if (source.includes("IF v_role NOT IN")) {
  throw new Error('operational workspace authorization still uses a single resolved role');
}
const requiredChecks = [
  "public.has_role(auth.uid(),'admin')",
  "public.has_role(auth.uid(),'practitioner')",
  "public.has_role(auth.uid(),'nurse')",
  "public.has_role(auth.uid(),'midwife')",
  "public.has_role(auth.uid(),'specialist_nurse')"
];
for (const needle of requiredChecks) {
  if (!source.includes(needle)) throw new Error('operational workspace is missing multi-role authorization check: ' + needle);
}
if (!source.includes("CREATE OR REPLACE FUNCTION public.get_operational_workspace(_module text, _limit integer DEFAULT 200)")) {
  throw new Error('operational workspace function missing');
}
console.log('Operational workspace multi-role authorization contract passed');
