#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root = process.cwd();
const migrationDir = path.join(root, "supabase", "migrations");
const migrations = [];

function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (/\.sql$/.test(entry.name)) migrations.push(full);
  }
}

walk(migrationDir);

const findings = [];

for (const file of migrations) {
  const source = fs.readFileSync(file, "utf8");
  const dropIndexStatements = source.match(/\bDROP\s+INDEX(?:\s+CONCURRENTLY)?\s+(?:IF\s+EXISTS\s+)?[^;]+;/gi) ?? [];

  for (const statement of dropIndexStatements) {
    if (!/approved-index-removal\s*:/i.test(source)) {
      findings.push({
        file,
        statement: statement.replace(/\s+/g, " ").trim(),
      });
    }
  }
}

assert.equal(
  findings.length,
  0,
  findings
    .map(
      ({ file, statement }) =>
        `index removal requires an explicit '-- approved-index-removal:' rationale: ${file}: ${statement}`,
    )
    .join("\n"),
);

console.log(
  `Index lifecycle contract passed across ${migrations.length} migration files: no unreviewed DROP INDEX statements detected.`,
);
console.log(
  "Unused-index advisor findings remain an evidence-review queue; this contract intentionally does not delete indexes automatically.",
);
