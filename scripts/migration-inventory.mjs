import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

// Inventory only: never rename files, execute SQL, or modify a migration ledger.
export function inspectMigrationDirectory(directory) {
  const migrations = [];
  const invalidEntries = [];
  const byVersion = new Map();
  for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name === '.gitkeep' || entry.name === 'README.md') continue;
    const match = /^(\d{14})_(.+)\.sql$/.exec(entry.name);
    if (!entry.isFile() || !match) {
      invalidEntries.push(entry.name);
      continue;
    }
    const sql = fs.readFileSync(path.join(directory, entry.name));
    const migration = {
      version: match[1], name: match[2], file: entry.name,
      sha256: createHash('sha256').update(sql).digest('hex'),
    };
    if (!sql.toString('utf8').trim()) invalidEntries.push(`${entry.name} (empty SQL)`);
    migrations.push(migration);
    const group = byVersion.get(migration.version) ?? [];
    group.push(migration);
    byVersion.set(migration.version, group);
  }
  const collisions = [...byVersion.entries()]
    .filter(([, entries]) => entries.length > 1)
    .map(([version, entries]) => ({ version, files: entries.map(entry => entry.file) }));
  return { migrations, collisions, invalidEntries };
}

export function migrationInventoryErrors(inventory) {
  const errors = inventory.invalidEntries.map(entry => `Unrecognized or empty migration entry: ${entry}`);
  for (const collision of inventory.collisions) {
    errors.push(`Duplicate migration version ${collision.version}: ${collision.files.join(', ')}`);
  }
  if (inventory.migrations.length === 0) errors.push('No migration SQL files found');
  return errors;
}

export function compareMigrationLedger(inventory, ledger) {
  if (!Array.isArray(ledger)) throw new Error('Ledger must be a JSON array of version/name records from a current read-only database query');
  const remote = new Map();
  for (const row of ledger) {
    if (!row || typeof row.version !== 'string' || !/^\d{14}$/.test(row.version)
      || typeof row.name !== 'string' || !row.name.trim() || remote.has(row.version)) {
      throw new Error('Ledger contains an invalid, unnamed, or duplicate version; do not infer applied identities');
    }
    remote.set(row.version, row.name);
  }
  const localVersions = new Set(inventory.migrations.map(entry => entry.version));
  const localOnly = inventory.migrations.filter(entry => !remote.has(entry.version));
  const remoteOnly = [...remote].filter(([version]) => !localVersions.has(version))
    .map(([version, name]) => ({ version, name }));
  const nameMismatches = inventory.migrations.filter(entry => remote.has(entry.version) && remote.get(entry.version) !== entry.name)
    .map(entry => ({ file: entry.file, version: entry.version, remoteName: remote.get(entry.version) }));
  return { localOnly, remoteOnly, nameMismatches };
}