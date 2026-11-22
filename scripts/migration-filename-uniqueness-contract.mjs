import path from "node:path";
import { inspectMigrationDirectory, migrationInventoryErrors } from './migration-inventory.mjs';

const dir=path.join(process.cwd(),"supabase","migrations");
const inventory = inspectMigrationDirectory(dir);
const errors = migrationInventoryErrors(inventory);
if (errors.length) {
  for (const error of errors) console.error(`[migration-filename-uniqueness] ${error}`);
  process.exitCode = 1;
} else {
  console.log(`[migration-filename-uniqueness] ${inventory.migrations.length} migration filenames have unique 14-digit versions`);
}
