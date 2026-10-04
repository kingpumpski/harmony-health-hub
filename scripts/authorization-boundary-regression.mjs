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
  [
    "notification_feature_enabled",
    [
      "_user_id",
      "auth.uid()",
      "_user_id is distinct from caller_id",
      "request.jwt.claim.role",
      "forbidden",
      "it_admin",
      "abs(hashtext(_user_id::text || ':' || _key)::bigint)",
    ],
  ],
  ["create_emergency_case", ["assert_patient_facility_context", "facility_id", "assigned_officer", "set search_path to ''"]],
  ["create_dental_record", ["assert_patient_facility_context", "facility_id", "performed_by", "set search_path to ''"]],
  ["create_anesthetic_assessment", ["assert_patient_facility_context", "facility_id", "cleared_by", "assessed_by", "set search_path to ''"]],
  ["create_patient_appointment", ["assert_patient_facility_context", "set search_path to ''"]],
  ["create_inpatient_review", ["assert_patient_facility_context", "facility_id", "set search_path to ''"]],
  ["create_maternity_episode_workflow", ["assert_patient_facility_context", "facility_id", "set search_path to ''"]],
  ["mark_meal_order_delivered", ["assert_patient_facility_context", "facility_id", "set search_path = ''"]],
  ["record_patient_deposit", ["assert_patient_facility_context", "facility_id", "set search_path = ''"]],
  ["prepare_patient_billable_items", ["assert_patient_facility_context", "facility_id", "set search_path = ''"]],
  ["activate_patient_visit_coverage", ["facility_id", "patient facility attribution is unresolved"]],
  ["create_patient_document", ["assert_patient_facility_context", "uploaded_by"]],
  ["create_patient_referral_workflow", ["patient facility attribution is unresolved", "active facility context is required"]],
  ["create_nursing_note", ["assert_patient_facility_context", "set search_path = ''"]],
  ["create_ophthalmology_exam", ["assert_patient_facility_context", "set search_path = ''"]],
  ["create_procedure_note", ["assert_patient_facility_context", "set search_path = ''"]],
  ["create_theatre_case", ["assert_patient_facility_context", "set search_path = ''"]],
  ["create_transfusion_record", ["assert_patient_facility_context", "set search_path = ''"]],
  ["create_walk_in_billable_service", ["assert_patient_facility_context", "set search_path = ''"]],
  ["record_triage_assessment_offline", ["assert_patient_facility_context", "set search_path = ''"]],
  ["upload_patient_document_metadata", ["assert_patient_facility_context", "set search_path = ''"]],
  ["create_care_transition_workflow", ["assert_patient_facility_context", "set search_path = ''"]],
  ["create_nursing_shift_handover", ["assert_patient_facility_context", "set search_path = ''"]],
  ["approve_lab_result", ["assert_patient_facility_context", "set search_path = ''"]],
  ["create_patient_admission", ["assert_patient_facility_context", "set search_path = ''"]],
  ["complete_ai_report_request", ["facility_id", "set search_path = ''"]],
  ["record_fertility_monitoring_workflow", ["assert_patient_facility_context", "set search_path = ''"]],
  ["record_maternity_observation_workflow", ["assert_patient_facility_context", "set search_path = ''"]],
  ["record_transfusion_event", ["assert_patient_facility_context", "set search_path = ''"]],
  ["transition_theatre_case", ["assert_patient_facility_context", "set search_path = ''"]],
];

const normalizedSql = sqlSource.toLowerCase();

for (const [name, tokens] of contracts) {
  const definitionPattern = new RegExp(
    "create\\s+(?:or\\s+replace\\s+)?function\\s+public\\." + name + "\\b",
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
  {
    signature: "public.activate_patient_visit_coverage(uuid,text,uuid,date)",
    definition: "create function public.activate_patient_visit_coverage",
  },
  {
    signature: "public.create_patient_document(uuid,text,text,text)",
    definition: "create function public.create_patient_document",
  },
  {
    signature: "public.create_patient_referral_workflow(uuid,text,text,text,text,text)",
    definition: "create function public.create_patient_referral_workflow",
  },
];

for (const { signature, definition } of explicitSearchPathContracts) {
  const definitionIndex = normalized.lastIndexOf(definition);
  const hasAlterOverride = normalized.includes(
    `alter function ${signature.toLowerCase()} set search_path = ''`,
  );
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
