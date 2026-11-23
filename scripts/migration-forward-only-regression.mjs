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
  console.log('[migration-forward-only-regression] forward additions pass; older additions, edits, deletions, and duplicate versions fail closed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
