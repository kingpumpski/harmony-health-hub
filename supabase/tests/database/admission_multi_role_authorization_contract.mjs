import fs from 'node:fs';

const source = fs.readFileSync('supabase/migrations/20260921121000_post_merge_runtime_role_lookup_fix.sql', 'utf8');

if (source.includes("SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;")) {
  throw new Error('admission authorization still depends on the first assigned role');
}
const requiredRoles = ['admin','practitioner','nurse','midwife','specialist_nurse'];
for (const role of requiredRoles) {
  const needle = "public.has_role(auth.uid(),'" + role + "')";
  if (!source.includes(needle)) throw new Error('missing multi-role authorization for ' + role);
}
if (!source.includes("CREATE OR REPLACE FUNCTION public.get_patient_admission_history(_patient_id uuid)")) throw new Error('admission history function missing');
if (!source.includes("CREATE OR REPLACE FUNCTION public.get_admission_workspace(_limit integer DEFAULT 200)")) throw new Error('admission workspace function missing');
console.log('Admission read multi-role authorization contract passed');
