import fs from 'node:fs';

const source = fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts', 'utf8');

const required = [
  'const callerRoleSet = new Set(',
  'const hasAnyRole = (roles: string[]) => roles.some((role) => callerRoleSet.has(role));',
  'if (!hasAnyRole(aiClinicalRoles))',
  'if (!hasAnyRole([\'admin\',\'practitioner\',\'nurse\',\'midwife\',\'specialist_nurse\']))',
  'if (!hasAnyRole([\'admin\',\'practitioner\']))'
];

for (const marker of required) {
  if (!source.includes(marker)) throw new Error('AI multi-role authorization contract failed: ' + marker);
}

if (source.includes('const callerRole = String(callerRoles[0]?.role ?? \'\');')) {
  throw new Error('AI authorization still depends on the first assigned role');
}

console.log('AI multi-role authorization contract passed');
