#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const migrationsDir = path.join(process.cwd(), "supabase/migrations");
const baseline = "20260929230000_appointment_facility_authorization_hardening.sql";

const files = fs.existsSync(migrationsDir)
  ? fs.readdirSync(migrationsDir)
      .filter((name) => /^\d+_.+\.sql$/.test(name))
      .sort()
      .filter((name) => name >= baseline)
  : [];

assert(files.length > 0, "authenticated SECURITY DEFINER exposure contract: no migrations found after baseline");

const sources = files.map((name) => ({
  name,
  sql: fs.readFileSync(path.join(migrationsDir, name), "utf8"),
}));

const allSource = sources.map(({ sql }) => sql).join("\n");

function functionDeclarations(sql) {
  const pattern = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.([a-z0-9_]+)\s*\(([^)]*)\)[\s\S]*?SECURITY\s+DEFINER/gi;
  return [...sql.matchAll(pattern)].map((match) => ({
    name: match[1],
    signature: match[2],
  }));
}

const declarations = sources.flatMap(({ name, sql }) =>
  functionDeclarations(sql).map((item) => ({ ...item, migration: name })),
);

assert(
  declarations.length > 0,
  "authenticated SECURITY DEFINER exposure contract: no new SECURITY DEFINER functions detected",
);

function hasExplicitRevoke(name, role) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    "REVOKE\\s+(?:ALL|EXECUTE)\\s+ON\\s+FUNCTION\\s+public\\." +
      escaped +
      "\\s*\\([^;]*\\)\\s+FROM\\s+([^;]+)",
    "gi",
  );
  return [...allSource.matchAll(pattern)].some((match) =>
    match[1]
      .split(",")
      .map((value) => value.trim().toLowerCase())
      .includes(role.toLowerCase()),
  );
}

function hasAuthenticatedGrant(name) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  return new RegExp(
    "GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\." +
      escaped +
      "\\s*\\([^;]*\\)\\s+TO\\s+authenticated",
    "i",
  ).test(allSource);
}

function hasPublicGrant(name) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  return new RegExp(
    "GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\." +
      escaped +
      "\\s*\\([^;]*\\)\\s+TO\\s+PUBLIC",
    "i",
  ).test(allSource);
}

for (const declaration of declarations) {
  assert(
    hasExplicitRevoke(declaration.name, "PUBLIC"),
    declaration.name + " introduced in " + declaration.migration +
      " must explicitly revoke PUBLIC EXECUTE",
  );
  assert(
    hasExplicitRevoke(declaration.name, "anon"),
    declaration.name + " introduced in " + declaration.migration +
      " must explicitly revoke anon EXECUTE",
  );
  assert(
    hasAuthenticatedGrant(declaration.name) ||
      hasExplicitRevoke(declaration.name, "authenticated"),
    declaration.name + " introduced in " + declaration.migration +
      " must explicitly grant authenticated EXECUTE or explicitly revoke authenticated EXECUTE for non-API functions",
  );
  assert(
    !hasPublicGrant(declaration.name),
    declaration.name + " must not explicitly grant PUBLIC EXECUTE",
  );
}

console.log(
  "Authenticated SECURITY DEFINER exposure contract passed: " +
    declarations.length +
    " newly introduced SECURITY DEFINER functions have explicit PUBLIC/anon denial and an explicit authenticated grant or denial.",
);
