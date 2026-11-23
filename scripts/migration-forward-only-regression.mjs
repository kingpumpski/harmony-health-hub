import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'harmony-forward-migration-'));
const run = (args, options = {}) => execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options });
const write = (name, sql = 'select 1;') => {
  const file = path.join(root, 'supabase/migrations', name);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, sql);
};
const validator = path.resolve('scripts/migration-forward-only-contract.mjs');
const check = (base) => spawnSync(process.execPath, [validator, base], { cwd: root, encoding: 'utf8' });
try {
  run(['init', '-b', 'main']);
  run(['config', 'user.email', 'migration-contract@example.invalid']);
  run(['config', 'user.name', 'Migration Contract']);
  write('20261024070000_baseline.sql');
  write('20261024070000_legacy_duplicate.sql');
  write('$(path)', '-- unversioned legacy artifact; never an active migration');
  fs.mkdirSync(path.join(root, 'supabase'), { recursive: true });
  fs.writeFileSync(path.join(root, 'supabase/migration-ledger-baseline.json'), JSON.stringify({
    schema_version: 1,
    project_ref: 'fixture',
    latest_version: '20261026141054',
    migration_count: 1,
    migrations: [{ version: '20261026141054', name: 'hosted_latest' }],
  }));
  run(['add', '.']); run(['commit', '-m', 'baseline']);
  const base = run(['rev-parse', 'HEAD']).trim();

  write('20261027000000_forward_fix.sql');
  run(['add', '.']); run(['commit', '-m', 'forward migration']);
  let result = check(base);
  assert.equal(result.status, 0, result.stderr);

  run(['checkout', '--detach', base]);
  const legacyArtifact = path.join(root, 'supabase/migrations/$(path)');
  const archivedArtifact = path.join(root, 'docs/engineering/migration-source-candidates/legacy-workflow-notification.sql.candidate');
  fs.mkdirSync(path.dirname(archivedArtifact), { recursive: true });
  fs.copyFileSync(legacyArtifact, archivedArtifact);
  fs.rmSync(legacyArtifact);
  run(['add', '-A']); run(['commit', '-m', 'archive invalid unversioned artifact']);
  result = check(base);
  assert.equal(result.status, 0, result.stderr);

  run(['checkout', '--detach', base]);
  fs.mkdirSync(path.dirname(archivedArtifact), { recursive: true });
  fs.writeFileSync(archivedArtifact, '-- altered archive must not authorize deletion');
  fs.rmSync(legacyArtifact);
  run(['add', '-A']); run(['commit', '-m', 'tamper with archived artifact']);
  result = check(base);
  assert.equal(result.status, 1, 'archiving the invalid artifact with changed contents must fail');

  run(['checkout', '--detach', base]);
  const ledgerManifestPath = path.join(root, 'supabase/migration-ledger-baseline.json');
  const ledgerManifest = JSON.parse(fs.readFileSync(ledgerManifestPath, 'utf8'));
  ledgerManifest.project_ref = 'tampered';
  fs.writeFileSync(ledgerManifestPath, JSON.stringify(ledgerManifest, null, 2));
  run(['add', '.']); run(['commit', '-m', 'tamper with hosted ledger baseline']);
  result = check(base);
  assert.equal(result.status, 1, 'changing the verified hosted ledger baseline must fail');

  run(['checkout', '--detach', base]);
  const appendOnlyManifest = JSON.parse(fs.readFileSync(ledgerManifestPath, 'utf8'));
  appendOnlyManifest.latest_version = '20261027000000';
  appendOnlyManifest.migration_count = 2;
  appendOnlyManifest.migrations.push({ version: '20261027000000', name: 'verified_new_hosted_migration' });
  fs.writeFileSync(ledgerManifestPath, JSON.stringify(appendOnlyManifest, null, 2));
  run(['add', '.']); run(['commit', '-m', 'append verified hosted ledger entry']);
  result = check(base);
  assert.equal(result.status, 0, result.stderr);

  run(['checkout', '--detach', base]);
  write('20261025000000_before_hosted_head.sql');
  run(['add', '.']); run(['commit', '-m', 'out of order migration']);
  result = check(base);
  assert.equal(result.status, 1, 'a new migration older than baseline must fail');

  run(['checkout', '--detach', base]);
  write('20261024070000_baseline.sql', 'select 2;');
  run(['add', '.']); run(['commit', '-m', 'rewrite applied history']);
  result = check(base);
  assert.equal(result.status, 1, 'editing a baseline migration must fail');

  run(['checkout', '--detach', base]);
  fs.rmSync(path.join(root, 'supabase/migrations/20261024070000_baseline.sql'));
  run(['add', '-A']); run(['commit', '-m', 'delete applied history']);
  result = check(base);
  assert.equal(result.status, 1, 'deleting a baseline migration must fail');

  run(['checkout', '--detach', base]);
  write('20261102000000_first.sql');
  write('20261102000000_second.sql');
  run(['add', '.']); run(['commit', '-m', 'duplicate versions']);
  result = check(base);
  assert.equal(result.status, 1, 'duplicate migration versions must fail');
  console.log('[migration-forward-only-regression] forward additions pass; byte-identical archival of the invalid unversioned artifact is allowed; changed archives, older additions, edits, deletions, and duplicate versions fail closed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
