#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const migrationsDir = path.join(process.cwd(), "supabase", "migrations");
const baselineMigration = "20260929230000_appointment_facility_authorization_hardening.sql";

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".sql")) out.push(full);
  }
  return out;
}

const files = walk(migrationsDir)
  .filter((file) => path.basename(file) >= baselineMigration)
  .sort();

const failures = [];
let definerCount = 0;

for (const file of files) {
  const source = fs.readFileSync(file, "utf8").replace(/--.*$/gm, "");
  const declarations = [
    ...source.matchAll(
      /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+((?:public|private|[a-zA-Z_][a-zA-Z0-9_]*)\.[a-zA-Z_][a-zA-Z0-9_]*)\s*\([^)]*\)[\s\S]*?\bSECURITY\s+DEFINER\b[\s\S]*?(?=CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+|$)/gi,
    ),
  ];

  for (const match of declarations) {
    const block = match[0];
    definerCount += 1;
    if (!/\bSET\s+search_path\s*=\s*''/i.test(block)) {
      failures.push(
        `${path.relative(process.cwd(), file)}: ${match[1]} SECURITY DEFINER must use SET search_path = ''`,
      );
    }
  }
}

assert.equal(
  failures.length,
  0,
  "SECURITY DEFINER creation contract failed:\n" + failures.join("\n"),
);

console.log(
  "SECURITY DEFINER creation contract passed for " +
    definerCount +
    " post-baseline migration declarations.",
);
