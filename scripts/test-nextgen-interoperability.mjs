import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const root = process.cwd();
const temp = mkdtempSync(join(tmpdir(), 'harmony-nextgen-interop-'));
const expect = (condition, message) => { if (!condition) throw new Error(message); };
const expectThrow = (fn, message) => { try { fn(); } catch { return; } throw new Error(message); };

try {
  execFileSync(
    process.platform === 'win32' ? 'npx.cmd' : 'npx',
    ['tsc', '--target', 'ES2022', '--module', 'commonjs', '--moduleResolution', 'node', '--skipLibCheck', '--esModuleInterop', '--outDir', temp,
      join(root, 'src/lib/nextGenContracts.ts'), join(root, 'src/lib/nextGenIntegrationRuntime.ts')],
    { cwd: root, stdio: 'inherit' },
  );

  const require = createRequire(import.meta.url);
  const contracts = require(join(temp, 'nextGenContracts.js'));
  const integration = require(join(temp, 'nextGenIntegrationRuntime.js'));
  const manifest = JSON.parse(readFileSync(join(root, 'platform/reference/interoperability-fixtures.json'), 'utf8'));

  expect(manifest.version === '1.0.0', 'Unexpected interoperability fixture manifest version');
  expect(Array.isArray(manifest.fixtures) && manifest.fixtures.length === 7, 'Expected exactly seven interoperability fixtures');

  const store = new Map();
  const runtimeStore = { find: (id) => store.get(id), enqueue: (record) => store.set(record.messageId, record) };
  const accepted = [];

  for (const fixture of manifest.fixtures) {
    const envelope = {
      messageId: `fixture-${fixture.id}`,
      correlationId: `correlation-${fixture.id}`,
      sourceSystem: 'synthetic-fixture-source',
      destinationSystem: 'harmony-health-hub',
      standard: fixture.standard,
      direction: fixture.direction,
      eventType: fixture.eventType,
      schemaVersion: fixture.schemaVersion,
      occurredAt: '2026-01-01T00:00:00.000Z',
      classification: fixture.classification,
      payload: fixture.payload,
    };

    expect(contracts.validateEnvelope(envelope), `Fixture failed structural validation: ${fixture.id}`);
    const first = integration.evaluateIncomingEnvelope(envelope, runtimeStore);
    expect(first.decision === 'accept', `Fixture was not accepted by delivery runtime: ${fixture.id}`);
    accepted.push(envelope);

    const duplicate = integration.evaluateIncomingEnvelope(envelope, runtimeStore);
    expect(duplicate.decision === 'duplicate', `Exact duplicate was not suppressed: ${fixture.id}`);
  }

  const collisionBase = accepted[0];
  const collision = integration.evaluateIncomingEnvelope({ ...collisionBase, payload: { ...collisionBase.payload, fixtureMutation: true } }, runtimeStore);
  expect(collision.decision === 'quarantine', 'Message-ID collision with altered content was not quarantined');

  const malformed = { ...accepted[1], messageId: 'fixture-malformed', payload: undefined };
  expect(!contracts.validateEnvelope(malformed), 'Malformed interoperability fixture was structurally accepted');
  expect(integration.evaluateIncomingEnvelope(malformed, runtimeStore).decision === 'reject', 'Malformed interoperability envelope was not rejected');

  const quarantined = { ...store.get(collisionBase.messageId), state: 'quarantined' };
  expect(integration.canReplay(quarantined, { authorised: false, confirmed: true }) === false, 'Unauthorized fixture replay was allowed');
  expect(integration.canReplay(quarantined, { authorised: true, confirmed: false }) === false, 'Unconfirmed fixture replay was allowed');
  const pending = integration.prepareReplay(quarantined, { authorised: true, confirmed: true });
  expect(pending.state === 'replay_pending', 'Authorized fixture replay did not enter replay_pending');
  const replayed = integration.markReplayed(pending, { authorised: true, confirmed: true });
  expect(replayed.state === 'replayed', 'Fixture replay did not reach replayed state');
  expectThrow(() => integration.prepareReplay(replayed, { authorised: true, confirmed: true }), 'Terminal replay state was replayed again');

  console.log(`Interoperability fixture delivery tests passed for ${manifest.fixtures.length} supported standards.`);
} finally {
  rmSync(temp, { recursive: true, force: true });
}
