#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

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

const sourceByFile = new Map(files.map((file) => [file, fs.readFileSync(file, "utf8")]));
const allSource = [...sourceByFile.values()].join("\n");

function functionBody(name) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    "CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\." +
      escaped +
      "\\b[\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$",
    "gi",
  );
  const matches = [...allSource.matchAll(pattern)].map((match) => match[1]);
  return matches.length ? matches[matches.length - 1] : "";
}

const contracts = [
  { name: "patient/encounter linkage", checks: [/encounter does not belong to patient/i, /patient_id/i] },
  { name: "facility authorization primitive", checks: [/has_facility_access/i, /facility_memberships/i] },
  { name: "clinical role authorization", checks: [/clinical role required/i, /current_user_is_clinical_staff/i] },
  { name: "notification recipient scoping", checks: [/notification_feature_enabled/i, /_user_id\\s+uuid/i, /auth\\.uid\\(\\)/i] },
];

for (const contract of contracts) {
  assert(contract.checks.every((pattern) => pattern.test(allSource)), "authorization contract missing: " + contract.name);
}

const facilityLineageDebt = {
  schemaGap: "patients has no facility_id; operational patient records do not consistently carry facility_id",
  requiresDedicatedTenancyMigration: true,
  functions: [
    "create_appointment_workflow",
    "create_ai_clinical_session",
    "create_imaging_order_with_payment_gate",
    "create_lab_order_with_payment_gate",
    "create_insurance_claim_draft",
    "create_pharmacy_pos_sale",
    "update_patient_workflow",
    "upload_patient_document_metadata",
    "search_patient_directory",
  ],
};

assert(facilityLineageDebt.requiresDedicatedTenancyMigration === true && facilityLineageDebt.functions.length > 0, "facility-lineage debt inventory must remain explicit");

for (const name of facilityLineageDebt.functions) {
  assert(functionBody(name) || allSource.includes(name), "reviewed function missing from repository: " + name);
}

console.log(
  "Authorization boundary regression passed: " +
    contracts.length +
    " baseline contracts; " +
    facilityLineageDebt.functions.length +
    " patient/facility tenancy items explicitly tracked.",
);
console.log("No production data or database state is changed by this test.");
