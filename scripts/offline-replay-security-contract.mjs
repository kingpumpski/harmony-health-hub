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
];


const triageInvariantMigration = fs.readFileSync(path.join(process.cwd(), 'supabase/migrations/20260929060000_triage_server_vital_requirement_parity.sql'), 'utf8');

const offlineReplayMigration = fs.readFileSync(path.join(process.cwd(), 'supabase/migrations/20260929062000_triage_offline_replay_race_safety.sql'), 'utf8');

const migrationRequired = [
  'REVOKE ALL ON FUNCTION public.record_triage_assessment_offline(',
  'GRANT EXECUTE ON FUNCTION public.record_triage_assessment_offline(',
  "v_priority = 'critical'",
  'WHERE id = _id',
  'already_recorded',
  'ON CONFLICT (id) DO NOTHING',
  'RETURNING id INTO v_inserted',
];

const triageInvariantRequired = [
  'ALTER TABLE public.triage_assessments',
  'triage_assessments_requires_measured_vital',
  'systolic IS NOT NULL OR',
  'oxygen_saturation IS NOT NULL OR',
  'weight_kg IS NOT NULL OR',
  'height_m IS NOT NULL',
];

const replayStart = source.indexOf('async function replayMutation');
const retryStart = source.indexOf('function retryDelayMs', replayStart);
const replaySection = replayStart >= 0 && retryStart > replayStart
  ? source.slice(replayStart, retryStart)
  : '';

const failures = [
  ...sourceRequired.filter((fragment) => !source.includes(fragment)),
  ...migrationRequired.filter((fragment) => !migration.includes(fragment)),
  ...['ON CONFLICT (id) DO NOTHING','RETURNING id INTO v_inserted','At least one measured vital sign is required'].filter((fragment) => !offlineReplayMigration.includes(fragment)),
  ...triageInvariantRequired.filter((fragment) => !triageInvariantMigration.includes(fragment)),
];

if (!triageSource.includes("rpc('record_triage_assessment', payload)")) {
  failures.push('Offline triage must use the authenticated record_triage_assessment RPC.');
}
if (!triageSource.includes('offlineAwareFetch converts that RPC to the explicit idempotent offline RPC')) {
  failures.push('Offline triage must document the explicit idempotent offline RPC replay path.');
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
  console.log('Offline replay security contract: 22/22 invariants present');
}
