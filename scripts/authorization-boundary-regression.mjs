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

const sourceByFile = new Map(
  files.map((file) => [file, fs.readFileSync(file, "utf8")]),
);
const allSource = [...sourceByFile.values()].join("\n");

function functionDefinitions(name) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    "CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\." +
      escaped +
      "\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+(\\$[A-Za-z0-9_]*\\$)([\\s\\S]*?)\\1",
    "gi",
  );
  return [...allSource.matchAll(pattern)].map((match) => ({
    definition: match[0],
    body: match[2],
  }));
}

function functionBodies(name) {
  return functionDefinitions(name).map((item) => item.body);
}

function functionBody(name) {
  const bodies = functionBodies(name);
  return bodies.length ? bodies[bodies.length - 1] : "";
}

function assertFunctionContract(name, checks) {
  const definitions = functionDefinitions(name);
  assert(definitions.length, "authorization contract function missing: " + name);
  definitions.forEach(({ definition }, index) => {
    for (const pattern of checks) {
      assert(
        pattern.test(definition),
        name + " overload #" + (index + 1) + ": missing " + pattern,
      );
    }
  });
}

const functionContracts = [
  {
    name: "create_imaging_order_with_payment_gate",
    checks: [/patient_id/i, /encounter does not belong to patient/i],
  },
  {
    name: "create_insurance_claim_draft",
    checks: [/patient_id/i, /invoice does not belong to patient/i],
  },
  {
    name: "create_pharmacy_pos_sale",
    checks: [/pharmacy or front desk role required/i, /patient_id/i],
  },
  {
    name: "create_appointment_workflow",
    checks: [
      /hms_patient_has_facility_access/i,
      /patient facility access denied/i,
      /SET\s+search_path\s*=\s*''/i,
      /FOR\s+UPDATE/i,
    ],
  },
  {
    name: "update_appointment_workflow",
    checks: [
      /hms_patient_has_facility_access/i,
      /appointment facility access denied/i,
      /SET\s+search_path\s*=\s*''/i,
      /FOR\s+UPDATE/i,
    ],
  },
  {
    name: "get_appointment_worklist",
    checks: [
      /hms_patient_has_facility_access/i,
      /SET\s+search_path\s*=\s*''/i,
    ],
  },
  {
    name: "transfer_patient_ward_bed_workflow",
    checks: [
      /current_user_facility_id/i,
      /Destination bed is outside the active facility/i,
      /Source bed is outside the active facility/i,
      /FOR\s+UPDATE/i,
    ],
  },
  {
    name: "hms_patient_has_facility_access",
    checks: [/patient_facility_access/i, /facility_memberships/i, /auth\.uid\(\)/i],
  },
  {
    name: "hms_assert_patient_facility_access",
    checks: [/hms_patient_has_facility_access/i, /patient facility access denied/i],
  },
  {
    name: "link_patient_to_current_facility",
    checks: [
      /hms_current_active_facility_id/i,
      /patient_facility_access/i,
      /facility linking is not permitted/i,
    ],
  },
  {
    name: "notification_feature_enabled",
    checks: [/_user_id/i, /auth\.uid\(\)/i],
  },
];

for (const contract of functionContracts) {
  assertFunctionContract(contract.name, contract.checks);
}

const tenancyMigrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260929160000_patient_facility_tenancy_foundation.sql",
);
assert(
  fs.existsSync(tenancyMigrationPath),
  "patient facility tenancy foundation migration missing",
);

const tenancyMigration = fs.readFileSync(tenancyMigrationPath, "utf8");
for (const pattern of [
  /CREATE TABLE IF NOT EXISTS public\.patient_facility_access/i,
  /ENABLE ROW LEVEL SECURITY/i,
  /hms_current_active_facility_id/i,
  /hms_patient_has_facility_access/i,
  /hms_assert_patient_facility_access/i,
  /link_patient_to_current_facility/i,
  /trg_auto_link_patient_to_active_facility/i,
  /SET search_path = ''/i,
  /REVOKE ALL ON TABLE public\.patient_facility_access FROM anon/i,
  /REVOKE ALL ON TABLE public\.patient_facility_access FROM authenticated/i,
  /GRANT SELECT ON TABLE public\.patient_facility_access TO authenticated/i,
  /REVOKE ALL ON FUNCTION public\.auto_link_patient_to_active_facility\(\) FROM PUBLIC/i,
]) {
  assert(
    pattern.test(tenancyMigration),
    "patient facility tenancy migration missing: " + pattern,
  );
}

const hardenedPatientFacilityFunctions = [
  "create_appointment_workflow",
];

const facilityLineageDebt = {
  schemaGap:
    "historical patient/facility lineage is incomplete; patients has no facility_id and operational patient records do not consistently carry facility_id",
  requiresDedicatedTenancyMigration: true,
  historicalBackfillPolicy:
    "do not infer or bulk-link ambiguous historical patients; require explicit authorized facility linking",
  functions: [
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

for (const name of hardenedPatientFacilityFunctions) {
  assert(
    functionBody(name),
    "hardened patient/facility function missing from repository: " + name,
  );
}

assert(
  facilityLineageDebt.requiresDedicatedTenancyMigration === true &&
    facilityLineageDebt.functions.length > 0,
  "facility-lineage debt inventory must remain explicit",
);

for (const name of facilityLineageDebt.functions) {
  assert(
    functionBody(name),
    "reviewed function missing from repository: " + name,
  );
}

const privilegedTenancyFunctions = [
  "hms_current_active_facility_id",
  "hms_patient_has_facility_access",
  "hms_assert_patient_facility_access",
  "link_patient_to_current_facility",
  "auto_link_patient_to_active_facility",
];

for (const name of privilegedTenancyFunctions) {
  const definitions = functionDefinitions(name);
  assert(definitions.length, "tenancy security-definer function missing: " + name);
  definitions.forEach(({ definition }, index) => {
    assert(
      /SECURITY\s+DEFINER/i.test(definition),
      name + " overload #" + (index + 1) + ": must remain SECURITY DEFINER",
    );
    assert(
      /SET\s+search_path\s*=\s*''/i.test(definition),
      name + " overload #" + (index + 1) + ": must use empty search_path",
    );
  });
}

console.log(
  "Authorization boundary regression passed: " +
    functionContracts.length +
    " function contracts across all overloads; " +
    hardenedPatientFacilityFunctions.length +
    " patient/facility functions hardened; " +
    facilityLineageDebt.functions.length +
    " remaining tenancy items explicitly tracked; " +
    privilegedTenancyFunctions.length +
    " tenancy security-definer contracts.",
);
console.log("No production data or database state is changed by this test.");
