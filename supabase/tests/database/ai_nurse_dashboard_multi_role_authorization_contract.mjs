import fs from 'node:fs';

const source = fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts', 'utf8');

if (source.includes('allowedRoles.includes(callerRole)')) {
  throw new Error('nurse_dashboard authorization still depends on an undefined first-role variable');
}
if (!source.includes('if (!hasAnyRole(allowedRoles)) throw new Error(\'Not authorised\');')) {
  throw new Error('nurse_dashboard must authorize against the complete caller role set');
}
if (!source.includes('const callerRoleSet = new Set')) {
  throw new Error('multi-role caller role set is missing');
}
console.log('AI nurse dashboard multi-role authorization contract passed');
