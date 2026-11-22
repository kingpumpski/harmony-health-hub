import fs from 'node:fs';
import path from 'node:path';
import { inspectMigrationDirectory, migrationInventoryErrors, compareMigrationLedger } from './migration-inventory.mjs';

const args = process.argv.slice(2);
if (args.length !== 0 && !(args.length === 2 && args[0] === '--ledger')) {
  console.error('Usage: npm run migration:parity -- [--ledger /path/to/current-ledger.json]');
  process.exit(1);
}
try {
  const inventory = inspectMigrationDirectory(path.join(process.cwd(), 'supabase/migrations'));
  const errors = migrationInventoryErrors(inventory);
  const comparison = args.length ? compareMigrationLedger(inventory, JSON.parse(fs.readFileSync(args[1], 'utf8'))) : null;
  const parityDiscrepancies = comparison
    ? comparison.localOnly.length + comparison.remoteOnly.length + comparison.nameMismatches.length : null;
  console.log(JSON.stringify({
    status: errors.length || parityDiscrepancies ? 'discrepancies' : comparison ? 'ledger-identities-match' : 'unverified',
    notice: 'Read-only inventory. Matching names and versions does not prove SQL, schema, privileges, RLS, or deployed parity; verify those separately. Never renumber applied history from this report.',
    ledgerProvided: Boolean(comparison),
    migrationCount: inventory.migrations.length,
    collisions: inventory.collisions,
    invalidEntries: inventory.invalidEntries,
    comparison,
    migrations: inventory.migrations,
  }, null, 2));
  // An absent ledger must never produce a green parity check.
  if (errors.length || !comparison || parityDiscrepancies) process.exitCode = 1;
} catch (error) {
  console.error(`[migration-parity] ${error instanceof Error ? error.message : 'Inspection failed'}`);
  process.exitCode = 1;
}