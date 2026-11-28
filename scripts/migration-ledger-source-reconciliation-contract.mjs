import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const manifest = JSON.parse(readFileSync(path.join(root, 'docs/engineering/migration-ledger-source-reconciliation-2026-11-27.json'), 'utf8'));
const ledger = JSON.parse(readFileSync(path.join(root, 'supabase/migration-ledger-baseline.json'), 'utf8'));
const migrationDir = path.join(root, 'supabase/migrations');
const files = readdirSync(migrationDir, { withFileTypes: true })
  .filter(entry => entry.isFile() && /^\d{14}_.+\.sql$/.test(entry.name))
  .map(entry => {
    const bytes = readFileSync(path.join(migrationDir, entry.name));
    const blobHeader = Buffer.from(`blob ${bytes.length}\0`);
    const gitBlobSha = createHash('sha1').update(Buffer.concat([blobHeader, bytes])).digest('hex');
    return { name: entry.name, path: `supabase/migrations/${entry.name}`, git_blob_sha: gitBlobSha };
  });
const byVersion = new Map();
const byName = new Map();
for (const file of files) {
  const version = file.name.slice(0, 14);
  const name = file.name.slice(15, -4);
  byVersion.set(version, [...(byVersion.get(version) ?? []), file]);
  byName.set(name, [...(byName.get(name) ?? []), file]);
}

assert.equal(manifest.schema_version, 1, 'unsupported source reconciliation schema');
assert.equal(manifest.hosted_ledger_project_ref, ledger.project_ref, 'manifest project reference must match the saved hosted ledger');
assert.equal(manifest.hosted_ledger_captured_at, ledger.captured_at, 'manifest ledger capture must match');
assert.equal(manifest.entries.length, ledger.migration_count, 'manifest must cover every hosted ledger entry');
assert.equal(files.length, manifest.counts.repository_migration_files, 'repository migration file count drifted');

const counts = { exact_identity_source_present: 0, version_present_name_mismatch: 0, version_absent: 0, same_name_candidate: 0, no_same_name_candidate: 0 };
for (let index = 0; index < ledger.migrations.length; index += 1) {
  const applied = ledger.migrations[index];
  const row = manifest.entries[index];
  assert.equal(row.version, applied.version, `ledger version drift at index ${index}`);
  assert.equal(row.name, applied.name, `ledger name drift at index ${index}`);
  const sameVersion = byVersion.get(applied.version) ?? [];
  const sameName = byName.get(applied.name) ?? [];
  const exact = sameVersion.find(file => file.name === `${applied.version}_${applied.name}.sql`);
  const status = exact ? 'exact_identity_source_present' : sameVersion.length ? 'version_present_name_mismatch' : 'version_absent';
  assert.equal(row.status, status, `source status drift for ${applied.version}`);
  assert.deepEqual(row.same_version_files.map(file => ({ path: file.path, git_blob_sha: file.git_blob_sha })),
    sameVersion.map(file => ({ path: file.path, git_blob_sha: file.git_blob_sha })), `same-version file inventory drift for ${applied.version}`);
  assert.deepEqual(row.same_name_candidates.map(file => ({ path: file.path, git_blob_sha: file.git_blob_sha })),
    sameName.map(file => ({ path: file.path, git_blob_sha: file.git_blob_sha })), `same-name candidate inventory drift for ${applied.version}`);
  for (const recorded of [...row.same_version_files, ...row.same_name_candidates]) {
    const local = files.find(file => file.path === recorded.path);
    assert.ok(local, `recorded candidate missing: ${recorded.path}`);
    assert.equal(local.git_blob_sha, recorded.git_blob_sha, `Git blob changed: ${recorded.path}`);
  }
  counts[status] += 1;
  if (status === 'version_absent' && sameName.length) counts.same_name_candidate += 1;
  else if (status === 'version_absent') counts.no_same_name_candidate += 1;
}
const expectedCounts = {
  exact_identity_source_present: manifest.counts.exact_identity_sources,
  version_present_name_mismatch: manifest.counts.version_present_name_mismatch,
  version_absent: manifest.counts.hosted_versions_absent_from_repository,
  same_name_candidate: manifest.counts.absent_versions_with_same_name_candidate,
  no_same_name_candidate: manifest.counts.absent_versions_without_same_name_candidate,
};
for (const [key, value] of Object.entries(counts)) assert.equal(value, expectedCounts[key], `count drift: ${key}`);
assert.equal(counts.exact_identity_source_present + counts.version_present_name_mismatch + counts.version_absent, ledger.migration_count);

console.log(`[migration-ledger-source-reconciliation] PASS: ${counts.exact_identity_source_present} exact source identities, ${counts.version_present_name_mismatch} same-version/name mismatches, ${counts.version_absent} absent hosted versions; candidate matches are not treated as proven deployed SQL.`);
