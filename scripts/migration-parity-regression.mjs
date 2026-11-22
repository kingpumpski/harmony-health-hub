import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { inspectMigrationDirectory, migrationInventoryErrors, compareMigrationLedger } from './migration-inventory.mjs';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'harmony-migration-parity-'));
const dir = path.join(root, 'supabase/migrations');
fs.mkdirSync(dir, { recursive: true });
const put = (name, sql = 'SELECT 1;') => fs.writeFileSync(path.join(dir, name), sql);
try {
  put('20260912003000_first.sql');
  put('20260912003000_second.sql');
  put('20260912010000_third.sql');
  put('20260912010000_fourth.sql');
  put('$(path)');
  put('invalid.sql');
  put('20260912020000_empty.sql', '   ');
  let inventory = inspectMigrationDirectory(dir);
  assert.equal(inventory.collisions.length, 2, 'all conflicting versions must be reported, not only the first');
  assert.deepEqual(inventory.collisions[0].files, ['20260912003000_first.sql', '20260912003000_second.sql']);
  assert.deepEqual(inventory.invalidEntries, ['$(path)', '20260912020000_empty.sql (empty SQL)', 'invalid.sql']);
  assert.equal(migrationInventoryErrors(inventory).length, 5);
  const before = fs.readFileSync(path.join(dir, '20260912003000_first.sql'));
  const compared = compareMigrationLedger(inventory, [
    { version: '20260912003000', name: 'first' },
    { version: '20260916002251', name: 'canonical_remote_schema' },
  ]);
  assert.equal(compared.localOnly.length, 3);
  assert.deepEqual(compared.nameMismatches, [{ file: '20260912003000_second.sql', version: '20260912003000', remoteName: 'first' }]);
  assert.deepEqual(compared.remoteOnly, [{ version: '20260916002251', name: 'canonical_remote_schema' }]);
  assert.deepEqual(fs.readFileSync(path.join(dir, '20260912003000_first.sql')), before, 'inspection must never rewrite SQL');
  assert.throws(() => compareMigrationLedger(inventory, [{ version: '20260912003000', name: '' }]), /invalid/);
  assert.throws(() => compareMigrationLedger(inventory, [
    { version: '20260912003000', name: 'first' }, { version: '20260912003000', name: 'first' },
  ]), /duplicate/);
  assert.throws(() => compareMigrationLedger(inventory, {}), /JSON array/);
  assert.equal(migrationInventoryErrors({ migrations: [], invalidEntries: [], collisions: [] }).length, 1);

  for (const name of fs.readdirSync(dir)) fs.rmSync(path.join(dir, name));
  put('20260912003000_first.sql');
  inventory = inspectMigrationDirectory(dir);
  assert.deepEqual(migrationInventoryErrors(inventory), []);
  assert.deepEqual(compareMigrationLedger(inventory, [{ version: '20260912003000', name: 'first' }]), {
    localOnly: [], remoteOnly: [], nameMismatches: [],
  });
  const cli = path.resolve('scripts/migration-parity.mjs');
  let result = spawnSync(process.execPath, [cli], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 1, 'missing live history must not pass parity');
  assert.equal(JSON.parse(result.stdout).status, 'unverified');
  const ledger = path.join(root, 'ledger.json');
  fs.writeFileSync(ledger, JSON.stringify([{ version: '20260912003000', name: 'first' }]));
  result = spawnSync(process.execPath, [cli, '--ledger', ledger], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).status, 'ledger-identities-match');
  put('20260912003000_second.sql');
  result = spawnSync(process.execPath, [cli, '--ledger', ledger], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 1, 'matching one deployed identity cannot excuse a collision');
  assert.equal(JSON.parse(result.stdout).collisions.length, 1);
  fs.writeFileSync(ledger, '{broken');
  result = spawnSync(process.execPath, [cli, '--ledger', ledger], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 1, 'unreadable history must fail closed');
  console.log('[migration-parity-regression] complete collision diagnostics, ignored SQL, non-mutating ledger comparisons, and fail-closed CLI checks passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}