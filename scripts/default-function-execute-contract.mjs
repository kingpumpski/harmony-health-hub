import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root = process.cwd();
const migrationsDir = path.join(root, "supabase", "migrations");
const files = fs.existsSync(migrationsDir)
  ? fs.readdirSync(migrationsDir).filter((name) => name.endsWith(".sql"))
  : [];
const source = files.map((name) => fs.readFileSync(path.join(migrationsDir, name), "utf8")).join("\n");

assert.match(
  source,
  /ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+postgres\s+IN\s+SCHEMA\s+public[\s\S]*?REVOKE\s+EXECUTE\s+ON\s+FUNCTIONS\s+FROM\s+PUBLIC/i,
  "public-schema default function EXECUTE must be revoked from PUBLIC",
);
assert.match(
  source,
  /ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+postgres\s+IN\s+SCHEMA\s+public[\s\S]*?REVOKE\s+EXECUTE\s+ON\s+FUNCTIONS\s+FROM\s+anon/i,
  "public-schema default function EXECUTE must be revoked from anon",
);
assert.match(
  source,
  /ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+postgres\s+IN\s+SCHEMA\s+public[\s\S]*?REVOKE\s+EXECUTE\s+ON\s+FUNCTIONS\s+FROM\s+authenticated/i,
  "public-schema default function EXECUTE must be revoked from authenticated",
);

console.log("[default-function-execute] secure-by-default migration contract passed");
