import { execFileSync } from 'node:child_process';
import path from 'node:path';

function git(args, options = {}) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options }).trim();
}

function fail(message) {
  console.error(`[migration-forward-only] ${message}`);
  process.exitCode = 1;
}

const requestedBase = process.argv[2] || (process.env.GITHUB_BASE_REF ? `origin/${process.env.GITHUB_BASE_REF}` : 'origin/main');
try {
  const mergeBase = git(['merge-base', requestedBase, 'HEAD']);
  const changed = git(['diff', '--name-status', '--no-renames', `${mergeBase}...HEAD`, '--', 'supabase/migrations']);
  const baseFiles = git(['ls-tree', '-r', '--name-only', mergeBase, '--', 'supabase/migrations'])
    .split('\n').filter(file => file.endsWith('.sql'));
  const versions = baseFiles.map(file => /^(\d{14})_.+\.sql$/.exec(path.basename(file))?.[1]).filter(Boolean);
  const latestBaseVersion = versions.sort().at(-1) ?? null;
  const changes = changed ? changed.split('\n').map(line => {
    const [status, file] = line.split('\t');
    return { status, file };
  }) : [];
  const errors = [];

  for (const change of changes) {
    if (change.status !== 'A') {
      errors.push(`Existing migration history is immutable: ${change.status} ${change.file}. Add a new forward migration instead.`);
      continue;
    }
    const match = /^(\d{14})_[a-z0-9_]+\.sql$/.exec(path.basename(change.file));
    if (!match) {
      errors.push(`New migration has an invalid filename: ${change.file}`);
      continue;
    }
    if (latestBaseVersion && match[1] <= latestBaseVersion) {
      errors.push(`New migration ${change.file} must sort after the baseline's latest version ${latestBaseVersion}.`);
    }
  }

  // Existing baseline collisions are legacy debt, not newly introduced changes.
  // The migration inventory contract reports them separately for controlled reconciliation.
  const addedByVersion = new Map();
  for (const change of changes.filter(item => item.status === 'A')) {
    const match = /^(\d{14})_[a-z0-9_]+\.sql$/.exec(path.basename(change.file));
    if (!match) continue;
    const previous = addedByVersion.get(match[1]);
    if (previous) errors.push(`New migrations reuse version ${match[1]}: ${previous} and ${change.file}`);
    else addedByVersion.set(match[1], change.file);
  }

  if (errors.length) {
    for (const error of errors) fail(error);
  } else {
    console.log(`[migration-forward-only] ${changes.length} migration path change(s) comply with immutable history and forward-only version ordering (baseline latest: ${latestBaseVersion ?? 'none'}).`);
  }
} catch (error) {
  fail(`Unable to verify migration ancestry against "${requestedBase}". Ensure the base ref is fetched; refusing to guess. ${error instanceof Error ? error.message : ''}`);
}
