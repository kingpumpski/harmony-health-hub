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
const sqlSource = files
  .filter((file) => file.endsWith(".sql"))
  .map((file) => fs.readFileSync(file, "utf8"))
  .join("\n");
const source = files.map((file) => fs.readFileSync(file, "utf8")).join("\n");

const contracts = [
  ["create_imaging_order_with_payment_gate", ["patient_id", "encounter does not belong to patient"]],
  ["create_insurance_claim_draft", ["patient_id", "invoice does not belong to patient"]],
  ["create_pharmacy_pos_sale", ["pharmacy or front desk role required", "patient_id"]],
  ["transfer_patient_ward_bed_workflow", ["current_user_facility_id", "FOR UPDATE"]],
  ["notification_feature_enabled", ["_user_id", "auth.uid()", "_user_id is distinct from caller_id", "request.jwt.claim.role", "forbidden", "it_admin", "abs(hashtext(_user_id::text || ':' || _key)::bigint")]],
  ["create_emergency_case", ["assert_patient_facility_context", "facility_id", "assigned_officer", "set search_path to ''"]],
  ["create_dental_record", ["assert_patient_facility_context", "facility_id", "performed_by", "set search_path to ''"]],
  ["create_anesthetic_assessment", ["assert_patient_facility_context", "facility_id", "cleared_by", "assessed_by", "set search_path to ''"]],
  ["create_patient_appointment", ["assert_patient_facility_context", "set search_path to ''"]],
  ["create_inpatient_review", ["assert_patient_facility_context", "facility_id", "set search_path to ''"]],
  ["create_maternity_episode_workflow", ["assert_patient_facility_context", "facility_id", "set search_path to ''"]],
];

for (const [name, tokens] of contracts) {
  const normalizedSql = sqlSource.toLowerCase();
  const definitionPattern = new RegExp(
    `(?:create\\s+(?:or\\s+replace\\s+)?function)\\s+public\\.${name}\\b`,
    "g",
  );
  const matches = [...normalizedSql.matchAll(definitionPattern)];
  assert(matches.length > 0, `authorization contract function missing: ${name}`);
  const index = matches.at(-1).index;
  const section = normalizedSql.slice(index, index + 12000);
  for (const token of tokens) {
    assert(section.includes(token.toLowerCase()), `${name}: missing ${token}`);
  }
}

const normalized = source.replace(/\s+/g, " ").toLowerCase();
const explicitSearchPathContracts = [
  {
    signature: "public.transfer_patient_ward_bed_workflow(uuid,uuid,uuid,uuid,text,text)",
    definition: "create function public.transfer_patient_ward_bed_workflow",
  },
  {
    signature: "public.create_admission_workflow(uuid,text,text,text)",
    definition: "create function public.create_admission_workflow",
  },
  {
    signature: "public.create_ward_unit(text,text,text,text)",
    definition: "create function public.create_ward_unit",
  },
];

for (const { signature, definition } of explicitSearchPathContracts) {
  const definitionIndex = normalized.lastIndexOf(definition);
  const hasAlterOverride = normalized.includes(`alter function ${signature.toLowerCase()} set search_path = ''`);
  const hasCreateOverride =
    definitionIndex >= 0 &&
    normalized.slice(definitionIndex, definitionIndex + 12000).includes("set search_path = ''");

  assert(
    hasAlterOverride || hasCreateOverride,
    `${signature} must have an explicit empty search_path override`,
  );
}

console.log("Authorization boundary regression passed: authentication, ownership, workflow-state, concurrency, and privilege contracts remain covered.");
console.log("No production data or database state is changed by this test.");
