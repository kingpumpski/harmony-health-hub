import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const migrationDir = path.join(root, 'supabase', 'migrations');
const manifestPath = path.join(root, 'docs', 'engineering', 'migration-collision-evidence-manifest-2026-11-26.json');
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const entries = await readdir(migrationDir, { withFileTypes: true });
const sqlFiles = entries
  .filter((entry) => entry.isFile() && /^\d{14}_.+\.sql$/.test(entry.name))
  .map((entry) => entry.name)
  .sort();

const byVersion = new Map();
for (const file of sqlFiles) {
  const version = file.slice(0, 14);
  const files = byVersion.get(version) ?? [];
  files.push(file);
  byVersion.set(version, files);
}
const actualGroups = [...byVersion.entries()]
  .filter(([, files]) => files.length > 1)
  .sort(([a], [b]) => a.localeCompare(b));
const expectedGroups = [...manifest.groups].sort((a, b) => a.version.localeCompare(b.version));

assert.equal(manifest.schema_version, 1, 'Unsupported migration collision evidence manifest schema');
assert.equal(manifest.migration_directory, 'supabase/migrations', 'Manifest migration directory must remain explicit');
assert.equal(expectedGroups.length, manifest.duplicate_group_count, 'Manifest duplicate group count is inconsistent');
assert.equal(actualGroups.length, expectedGroups.length,
  `Collision group count drifted: manifest=${expectedGroups.length}, repository=${actualGroups.length}`);

let collidingFileCount = 0;
for (let index = 0; index < expectedGroups.length; index += 1) {
  const expected = expectedGroups[index];
  const [actualVersion, actualFiles] = actualGroups[index];
  assert.equal(expected.version, actualVersion, `Unexpected collision version at index ${index}`);
  assert.deepEqual([...expected.files].sort(), actualFiles,
    `Collision file inventory drifted for version ${expected.version}`);

  const flattenedTiers = expected.ordered_tiers.flat();
  assert.equal(new Set(flattenedTiers).size, flattenedTiers.length,
    `Ordering evidence repeats a file for version ${expected.version}`);
  if (expected.status === 'blocked_diverged_history') {
    assert.equal(expected.ordered_tiers.length, 0,
      `Diverged history must not claim an execution order for ${expected.version}`);
  } else {
    assert.deepEqual([...flattenedTiers].sort(), [...expected.files].sort(),
      `Ordering tiers must account for every colliding file exactly once for ${expected.version}`);
  }
  assert.ok(expected.commit_evidence && expected.caveat,
    `Every collision group requires provenance and caveat text: ${expected.version}`);
  collidingFileCount += actualFiles.length;
}

assert.equal(collidingFileCount, manifest.colliding_file_count, 'Manifest colliding file count is inconsistent');
for (const sharedSet of manifest.shared_commit_sets ?? []) {
  assert.ok(sharedSet.commit && sharedSet.meaning, 'Shared commit sets require a commit and interpretation');
  for (const file of sharedSet.files) {
    assert.ok(sqlFiles.includes(path.basename(file)), `Shared-commit migration is missing: ${file}`);
  }
}

console.log(
  `[migration-collision-evidence] PASS: ${actualGroups.length} duplicate-version groups / ${collidingFileCount} files match the evidence manifest. This validates inventory only; it does not authorize replay or establish deployed order.`
);
