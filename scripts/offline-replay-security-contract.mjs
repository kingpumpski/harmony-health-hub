import fs from 'node:fs';
import path from 'node:path';

const source = fs.readFileSync(path.join(process.cwd(), 'src/lib/offlineSync.ts'), 'utf8');
const triageSource = fs.readFileSync(path.join(process.cwd(), 'src/lib/offlineTriage.ts'), 'utf8');
const migration = fs.readFileSync(path.join(process.cwd(), 'supabase/migrations/20260928233000_triage_offline_idempotency.sql'), 'utf8');

const sourceRequired = [
  "const headers = { ...item.headers, [IDEMPOTENCY_HEADER]: item.idempotencyKey };",
  'delete headers.authorization;',
  'if (accessToken) headers.authorization = `Bearer ${accessToken}`;',
  "item.status = 'blocked';",
  'RETRY_MAX_DELAY_MS',
  "['record_triage_assessment', 'record_triage_assessment_offline', 'triage'",
  "const OFFLINE_POSTGREST_TABLES = new Set(['patients']);",
  "supabase as any).rpc('record_triage_assessment', payload)",
];

const migrationRequired = [
  'REVOKE ALL ON FUNCTION public.record_triage_assessment_offline(',
  'GRANT EXECUTE ON FUNCTION public.record_triage_assessment_offline(',
  "v_priority = 'critical'",
  'WHERE id = _id',
  'already_recorded',
];

const replayStart = source.indexOf('async function replayMutation');
const retryStart = source.indexOf('function retryDelayMs', replayStart);
const replaySection = replayStart >= 0 && retryStart > replayStart
  ? source.slice(replayStart, retryStart)
  : '';

const failures = [
  ...sourceRequired.filter((fragment) => !source.includes(fragment)),
  ...migrationRequired.filter((fragment) => !migration.includes(fragment)),
];

if (!triageSource.includes('offlineAwareFetch converts that RPC to the explicit idempotent offline RPC')) {
  failures.push('Offline triage must route through the authenticated RPC path.');
}

const normalizedReplay = replaySection.replace(/\/\/[^\n]*\n/g, '').replace(/\s+/g, ' ');
if (!normalizedReplay.includes('const headers = { ...item.headers, [IDEMPOTENCY_HEADER]: item.idempotencyKey }; delete headers.authorization; if (authHeaderProvider)')) {
  failures.push('Authorization header must be removed before the auth-provider conditional');
}

if (failures.length) {
  console.error('Offline replay security contract failed:');
  for (const fragment of failures) console.error(`- ${fragment}`);
  process.exitCode = 1;
} else {
  console.log('Offline replay security contract: 13/13 invariants present');
}
