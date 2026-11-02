import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root = process.cwd();
const migrationsDir = path.join(root, "supabase", "migrations");
const files = fs.existsSync(migrationsDir)
  ? fs.readdirSync(migrationsDir).filter((name) => name.endsWith(".sql"))
  : [];
const source = files.map((name) => fs.readFileSync(path.join(migrationsDir, name), "utf8")).join("\n");
const migration = files.find((name) => name === "20260929200002_secure_default_function_execute_privileges.sql");
assert.ok(migration, "secure default function execution migration must exist");
const migrationSource = fs.readFileSync(path.join(migrationsDir, migration), "utf8");

assert.equal(
  (migrationSource.match(/ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public/gi) ?? []).length,
  3,
  "postgres default privileges must revoke EXECUTE from PUBLIC, anon, and authenticated",
);
assert.match(migrationSource, /DO \$supabase_admin_default_privileges\$/i, "supabase_admin defaults must be guarded by a role-membership check");
assert.match(migrationSource, /pg_has_role\(current_user, 'supabase_admin', 'MEMBER'\)/i, "supabase_admin defaults must only change when the migration owner has membership");
assert.equal(
  (migrationSource.match(/EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin/gi) ?? []).length,
  3,
  "supabase_admin default privileges must be guarded for all three API roles",
);
assert.equal(
  (migrationSource.match(/REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;/g) ?? []).length,
  1,
  "secure default migration must contain exactly one PUBLIC revoke",
);

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

for (const role of ["postgres", "supabase_admin"]) {
  const rolePattern = new RegExp(
    "ALTER\\\\s+DEFAULT\\\\s+PRIVILEGES\\\\s+FOR\\\\s+ROLE\\\\s+" +
      role +
      "\\\\s+IN\\\\s+SCHEMA\\\\s+public[\\\\s\\\\S]*?REVOKE\\\\s+EXECUTE\\\\s+ON\\\\s+FUNCTIONS\\\\s+FROM\\\\s+PUBLIC",
    "i",
  );
  assert.match(source, rolePattern, role + " public-schema default function EXECUTE must be revoked from PUBLIC");

  for (const target of ["anon", "authenticated"]) {
    const targetPattern = new RegExp(
      "ALTER\\\\s+DEFAULT\\\\s+PRIVILEGES\\\\s+FOR\\\\s+ROLE\\\\s+" +
        role +
        "\\\\s+IN\\\\s+SCHEMA\\\\s+public[\\\\s\\\\S]*?REVOKE\\\\s+EXECUTE\\\\s+ON\\\\s+FUNCTIONS\\\\s+FROM\\\\s+" +
        target,
      "i",
    );
    assert.match(source, targetPattern, role + " public-schema default function EXECUTE must be revoked from " + target);
  }
}

console.log("[default-function-execute] secure-by-default migration contract passed");
