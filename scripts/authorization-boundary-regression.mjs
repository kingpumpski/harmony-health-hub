#!/usr/bin/env node
/**
 * Authorization-boundary regression contract.
 * Static checks only; no production data is mutated.
 */
import fs from "node:fs";
import path from "node:path";

const roots = ["supabase/migrations", "supabase/functions", "supabase/tests"];
const files = [];

function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (/\.(sql|mjs|ts|tsx)$/.test(entry.name)) files.push(full);
  }
}

for (const root of roots) walk(path.join(process.cwd(), root));
const source = files.map((file) => fs.readFileSync(file, "utf8")).join("\n");

const contracts = [
  {
    name: "patient/encounter linkage",
    patterns: [/encounter does not belong to patient/i, /patient_id/i],
  },
  {
    name: "facility authorization",
    patterns: [/facility access denied/i, /facility_membership/i],
  },
  {
    name: "clinical role authorization",
    patterns: [/clinical role required/i, /current_user_is_clinical_staff/i],
  },
  {
    name: "notification recipient scoping",
    patterns: [/notification_feature_enabled/i, /_user_id uuid/i, /auth\.uid\(\)/i],
  },
];

const failures = contracts.filter(({ patterns }) => !patterns.every((p) => p.test(source)));

if (failures.length) {
  console.error("Authorization boundary regression failed:");
  for (const failure of failures) console.error(`- ${failure.name}`);
  process.exitCode = 1;
} else {
  console.log(`Authorization boundary regression passed (${contracts.length} contracts).`);
}
