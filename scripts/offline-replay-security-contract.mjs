import fs from 'node:fs';
import path from 'node:path';

const source = fs.readFileSync(path.join(process.cwd(), 'src/lib/offlineSync.ts'), 'utf8');
const required = [
  "const headers = { ...item.headers, [IDEMPOTENCY_HEADER]: item.idempotencyKey };",
  'delete headers.authorization;',
  'if (accessToken) headers.authorization = `Bearer ${accessToken}`;',
  "item.status = 'blocked';",
  'RETRY_MAX_DELAY_MS',
];

const replayStart = source.indexOf('async function replayMutation');
const retryStart = source.indexOf('function retryDelayMs', replayStart);
const replaySection = replayStart >= 0 && retryStart > replayStart
  ? source.slice(replayStart, retryStart)
  : '';

const failures = required.filter((fragment) => !source.includes(fragment));

if (
  !/const headers = \{ \.\.\.item\.headers, \[IDEMPOTENCY_HEADER\]: item\.idempotencyKey \};\s*delete headers\.authorization;\s*if \(authHeaderProvider\)/s.test(replaySection)
) {
  failures.push('Authorization header must be removed before the auth-provider conditional');
}

if (failures.length) {
  console.error('Offline replay security contract failed:');
  for (const fragment of failures) console.error(`- ${fragment}`);
  process.exitCode = 1;
} else {
  console.log('Offline replay security contract: 6/6 invariants present');
}
