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
  const headerPattern = /CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.([a-z0-9_]+)\\s*\\(([^)]*)\\)/gi;
  return [...sql.matchAll(headerPattern)].flatMap((match) => {
    const start = match.index;
    const nextMatch = /CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\./gi;
    nextMatch.lastIndex = start + match[0].length;
    const next = nextMatch.exec(sql);
    const source = sql.slice(start, next ? next.index : sql.length);
    if (!/SECURITY\\s+DEFINER/i.test(source)) return [];
    return [{
      name: match[1],
      signature: match[2],
      source,
    }];
  });
}

const declarations = sources.flatMap(({ name, sql }) =>
  functionDeclarations(sql).map((item) => ({ ...item, migration: name })),
);

assert(
  declarations.length > 0,
  "authenticated SECURITY DEFINER exposure contract: no SECURITY DEFINER functions detected",
);

function functionChunk(source) {
  return source ?? "";
}

function hasExplicitRevoke(name, role) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    "REVOKE\\s+(?:ALL|EXECUTE)\\s+ON\\s+FUNCTION\\s+public\\." +
      escaped +
      "\\s*\\([^;]*\\)\\s+FROM\\s+([^;]+)",
    "gi",
  );
  return [...allSource.matchAll(pattern)].some((match) =>
    match[1].split(",").map((value) => value.trim().toLowerCase()).includes(role.toLowerCase()),
  );
}

function hasAuthenticatedGrant(name) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  const grantPattern = new RegExp(
    "GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\." +
      escaped +
      "\\s*\\([^;]*\\)\\s+TO\\s+authenticated",
    "gi",
  );
  const revokePattern = new RegExp(
    "REVOKE\\s+(?:ALL|EXECUTE)\\s+ON\\s+FUNCTION\\s+public\\." +
      escaped +
      "\\s*\\([^;]*\\)\\s+FROM\\s+([^;]+)",
    "gi",
  );
  const grants = [...allSource.matchAll(grantPattern)];
  const revokes = [...allSource.matchAll(revokePattern)].filter((match) =>
    match[1].split(",").map((value) => value.trim().toLowerCase()).includes("authenticated"),
  );
  const lastGrant = grants.at(-1)?.index ?? -1;
  const lastRevoke = revokes.at(-1)?.index ?? -1;
  return lastGrant > lastRevoke;
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

function hasAuthorizationGuard(name, signature) {
  const chunk = functionChunk(name, signature);
  return [
    "auth.uid()",
    "current_user_role(",
    "current_user_has_role(",
    "current_user_facility_id(",
    "has_facility_access(",
    "is_clinical_staff(",
    "current_user_is_clinical_staff(",
    "has_role(",
  ].some((needle) => chunk.includes(needle));
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
  const grantsAuthenticatedInDeclaration = /GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.[a-z0-9_]+\\s*\\([^;]*\\)\\s+TO\\s+authenticated/i.test(
    declaration.source,
  );
  if (grantsAuthenticatedInDeclaration) {
    assert(
      hasAuthorizationGuard(declaration.source),
      declaration.name + " grants authenticated EXECUTE in its introducing migration but has no recognizable server-side authorization guard",
    );
  }
}

console.log(
  "Authenticated SECURITY DEFINER exposure contract passed: " +
    declarations.length +
    " SECURITY DEFINER functions have explicit execution boundaries and authenticated APIs have recognizable authorization guards.",
);
