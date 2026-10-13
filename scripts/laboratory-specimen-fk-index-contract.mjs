#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const migrationPath = path.join(
  process.cwd(),
  "supabase",
  "migrations",
  "20261013120000_index_lab_specimen_foreign_keys.sql",
);
const migration = fs.readFileSync(migrationPath, "utf8");
const expected = [
  ["idx_lab_specimens_collected_by", "collected_by"],
  ["idx_lab_specimens_recollection_of_id", "recollection_of_id"],
  ["idx_lab_specimens_rejected_by", "rejected_by"],
];

for (const [indexName, columnName] of expected) {
  const pattern = new RegExp(
    "CREATE\\s+INDEX\\s+IF\\s+NOT\\s+EXISTS\\s+" +
      indexName +
      "\\s+ON\\s+public\\.lab_specimens\\s*\\(\\s*" +
      columnName +
      "\\s*\\)",
    "i",
  );
  assert.match(
    migration,
    pattern,
    "Migration must create covering index " + indexName + " on " + columnName,
  );
}

assert.doesNotMatch(
  migration,
  /\\b(?:DROP\\s+(?:TABLE|INDEX|POLICY)|ALTER\\s+TABLE|CREATE\\s+POLICY|GRANT\\s|REVOKE\\s)\\b/i,
  "Index-only migration must not alter tables, policies, or grants",
);

const packageJson = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), "package.json"), "utf8"),
);
assert.match(
  packageJson.scripts.test,
  /npm run test:laboratory-specimen-fk-indexes/,
  "Required test chain must include the specimen foreign-key index contract",
);
assert.equal(
  packageJson.scripts["test:laboratory-specimen-fk-indexes"],
  "node scripts/laboratory-specimen-fk-index-contract.mjs",
  "Dedicated contract command must point to the new test",
);

console.log("Laboratory specimen foreign-key index contract passed.");
