import fs from 'node:fs';

const auth = fs.readFileSync('src/contexts/AuthContext.tsx', 'utf8');
const hub = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');

if (!auth.includes('roles: UserRole[];')) throw new Error('AuthContext does not expose the complete role set');
if (!auth.includes("supabase.from('user_roles').select('role').eq('user_id', supabaseUser.id).order('created_at', { ascending: true })")) {
  throw new Error('AuthContext must load all assigned roles');
}
if (!auth.includes("roles: roles.length ? roles : ['patient']")) throw new Error('AuthContext role fallback is missing');

if (!hub.includes('const roleSet = useMemo(() => new Set(user?.roles')) {
  throw new Error('Patient Hub does not derive authorization from the complete role set');
}
if (!hub.includes('roleSet].some((role) => clinicalRoles.has(role))')) {
  throw new Error('Patient Hub admission loading is still first-role dependent');
}
if (hub.includes("clinicalRoles.has(user?.role ?? '')")) {
  throw new Error('Patient Hub still gates admissions on only the primary role');
}

console.log('Patient Hub multi-role UI authorization contract passed');
