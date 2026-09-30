#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const repoRoot = process.cwd();
const manifestPath = path.join(repoRoot, "scripts", "patient-facility-boundary-manifest.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

assert.equal(manifest.version, 1, "unsupported patient-facility boundary manifest version");
assert.match(
  manifest.policy,
  /No patient-scoped workflow may be marked enforced/i,
  "manifest must preserve the enforcement gate",
);

const sourceFiles = [];
function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (/\.(sql|mjs|ts|tsx)$/.test(entry.name)) sourceFiles.push(full);
  }
}
for (const root of ["supabase/migrations", "supabase/functions", "supabase/tests"]) {
  walk(path.join(repoRoot, root));
}
const source = sourceFiles.map((file) => fs.readFileSync(file, "utf8")).join("\n");

const requiredFoundation = [
  "patient_facility_access",
  "hms_current_active_facility_id",
  "hms_patient_has_facility_access",
  "hms_assert_patient_facility_access",
  "link_patient_to_current_facility",
  "auto_link_patient_to_active_facility",
];

for (const symbol of requiredFoundation) {
  assert.match(source, new RegExp(symbol.replace(/[.*+?^$()|[\]\\]/g, "\\$&"), "i"), `tenancy foundation symbol missing: ${symbol}`);
}

const entries = Object.entries(manifest.functions);
assert(entries.length > 0, "patient-facility boundary manifest must not be empty");

for (const [name, status] of entries) {
  assert.match(status, /^(pending_tenancy_enforcement|hardened_pending_isolation_evidence|enforced|exempt)$/);
  assert.match(
    source,
    new RegExp(`(?:CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${name.replace(/[.*+?^$()|[\\]\\\\]/g, "\\\\$&")})`, "i"),
    `manifested function missing from repository: ${name}`,
  );

  if (status === "enforced") {
    const fnPattern = new RegExp(
      `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${name.replace(/[.*+?^$()|[\\]\\\\]/g, "\\\\$&")}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+(\\$[A-Za-z0-9_]*\\$)([\\s\\S]*?)\\1`,
      "i",
    );
    const matches = [...source.matchAll(fnPattern)];
    assert(matches.length, `unable to inspect enforced function: ${name}`);
    for (const match of matches) {
      assert.match(
        match[2],
        /hms_assert_patient_facility_access|hms_patient_has_facility_access/i,
        `${name}: every overload marked enforced requires patient-facility authorization`,
      );
    }
  }
}

assert(
  entries.some(([, status]) => status === "pending_tenancy_enforcement"),
  "at least one patient-scoped boundary must remain explicitly gated until isolated cross-facility validation",
);

console.log(`Patient-facility boundary contract passed: ${entries.length} patient-scoped functions are explicitly classified; ${entries.filter(([, s]) => s === "pending_tenancy_enforcement").length} remain gated pending isolated cross-facility validation.`);
console.log("No production data or database state is changed by this test.");
