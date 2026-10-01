#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const migrationsDir = path.join(process.cwd(), "supabase/migrations");
const baseline = "20260930170100_fix_start_appointment_encounter_btrim.sql";

const files = fs.existsSync(migrationsDir)
  ? fs.readdirSync(migrationsDir)
      .filter((name) => /^\d+_.+\.sql$/.test(name))
      .sort()
      .filter((name) => name > baseline)
  : [];

const sources = files.map((name) => ({
  name,
  sql: fs.readFileSync(path.join(migrationsDir, name), "utf8"),
}));

function declarations(sql) {
  const pattern = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.([a-z0-9_]+)\s*\([^)]*\)[\s\S]*?(?=CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.|$)/gi;
  return [...sql.matchAll(pattern)]
    .filter((match) => /SECURITY\s+DEFINER/i.test(match[0]))
    .map((match) => ({ name: match[1], source: match[0] }));
}

function hasGrant(source) {
  return /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.[a-z0-9_]+\s*\([^;]*\)\s+TO\s+authenticated/i.test(source);
}

function hasExplicitRevoke(source, role) {
  const escaped = role.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  return new RegExp(
    "REVOKE\\s+(?:ALL|EXECUTE)\\s+ON\\s+FUNCTION\\s+public\\.[a-z0-9_]+\\s*\\([^;]*\\)\\s+FROM\\s+[^;]*\\b" +
      escaped +
      "\\b",
    "i",
  ).test(source);
}

function hasAuthorizationGuard(source) {
  return [
    "auth.uid()",
    "current_user_role(",
    "current_user_has_role(",
    "current_user_facility_id(",
    "current_user_is_clinical_staff(",
    "has_facility_access(",
    "is_clinical_staff(",
    "has_role(",
  ].some((needle) => source.includes(needle));
}

const found = sources.flatMap(({ name, sql }) =>
  declarations(sql).map((declaration) => ({ ...declaration, migration: name })),
);

for (const declaration of found) {
  assert(
    hasExplicitRevoke(declaration.source, "PUBLIC"),
    declaration.name + " introduced in " + declaration.migration + " must explicitly revoke PUBLIC EXECUTE",
  );
  assert(
    hasExplicitRevoke(declaration.source, "anon"),
    declaration.name + " introduced in " + declaration.migration + " must explicitly revoke anon EXECUTE",
  );
  if (hasGrant(declaration.source)) {
    assert(
      hasAuthorizationGuard(declaration.source),
      declaration.name + " grants authenticated EXECUTE but has no recognizable server-side authorization guard",
    );
  }
}

console.log(
  "New SECURITY DEFINER authorization contract passed: " +
    found.length +
    " post-baseline SECURITY DEFINER declarations checked.",
);
