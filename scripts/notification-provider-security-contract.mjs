import fs from 'node:fs';

const config = fs.readFileSync('supabase/config.toml', 'utf8');
const provider = fs.readFileSync('supabase/functions/notification-provider-config/index.ts', 'utf8');

if (!/\[functions\.notification-provider-config\][\s\S]*?verify_jwt\s*=\s*true/.test(config)) {
  throw new Error('notification-provider-config must require JWT verification in supabase/config.toml');
}

for (const fragment of [
  'Authorization',
  'auth.getUser(token)',
  "['admin','it_admin']",
  'has_facility_access',
  'NOTIFICATION_CREDENTIAL_ENCRYPTION_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'credentials_ciphertext',
]) {
  if (!provider.includes(fragment)) {
    throw new Error(`notification-provider-config missing required security control: ${fragment}`);
  }
}

if (/console\.(log|error|warn)\([^)]*(password|api_key|credentials)/i.test(provider)) {
  throw new Error('notification-provider-config must not log provider credentials');
}

if (/JSON\.stringify\([^)]*credentials/i.test(provider)) {
  throw new Error('notification-provider-config must not serialize provider credentials into responses');
}

console.log('Notification provider Edge Function security contract passed');
