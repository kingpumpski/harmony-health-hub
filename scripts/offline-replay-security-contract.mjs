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

const failures = required.filter((fragment) => !source.includes(fragment));
if (failures.length) {
  console.error('Offline replay security contract failed:');
  for (const fragment of failures) console.error(`- Missing: ${fragment}`);
  process.exitCode = 1;
} else {
  console.log('Offline replay security contract: 5/5 invariants present');
}
