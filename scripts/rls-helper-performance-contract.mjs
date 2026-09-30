#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const dir = path.join(process.cwd(), "supabase", "migrations");
const baseline = "20260929214500_reconcile_revoked_role_helper_rls_policies.sql";
const helpers = [
  /public\.current_user_has_role\s*\(/gi,
  /public\.current_user_is_clinical_staff\s*\(/gi,
  /public\.current_user_can_edit_patient_record\s*\(/gi,
  /public\.hms_current_active_facility_id\s*\(/gi,
];

const files = fs
  .readdirSync(dir)
  .filter((name) => name.endsWith(".sql") && name >= baseline)
  .sort();

const failures = [];

function hasUncachedHelper(policyText, helperPattern) {
  helperPattern.lastIndex = 0;
  let match;
  while ((match = helperPattern.exec(policyText)) !== null) {
    const prefix = policyText.slice(Math.max(0, match.index - 40), match.index);
    if (!/\(\s*select\s+$/i.test(prefix)) return true;
  }
  return false;
}

for (const name of files) {
  const source = fs
    .readFileSync(path.join(dir, name), "utf8")
    .replace(/--.*$/gm, "");
  const policies = [
    ...source.matchAll(
      /(?:CREATE|ALTER)\s+POLICY[\s\S]*?;/gi,
    ),
  ];

  for (const match of policies) {
    for (const helper of helpers) {
      if (hasUncachedHelper(match[0], helper)) {
        failures.push(
          name +
            ": RLS policy must wrap stable no-arg authorization helper in (select ...)",
        );
      }
    }
  }
}

assert.equal(
  failures.length,
  0,
  "RLS helper performance contract failed:\n" + failures.join("\n"),
);

console.log(
  "RLS helper performance contract passed for " +
    files.length +
    " post-baseline migrations.",
);
