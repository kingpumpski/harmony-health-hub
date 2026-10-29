#!/usr/bin/env node
/**
 * Static migration-order/schema compatibility contract.
 *
 * This is intentionally a preflight: the clean Supabase replay and database
 * contract SQL tests remain mandatory and are not replaced by these checks.
 */
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const migrationsDir = path.join(root, "supabase", "migrations");
const fail = (message) => {
  console.error(`Migration contract failed: ${message}`);
  process.exitCode = 1;
};

if (!fs.existsSync(migrationsDir)) {
  fail("supabase/migrations directory is missing");
  process.exit(1);
}

const files = fs.readdirSync(migrationsDir).filter((name) => name.endsWith(".sql")).sort();
const versions = new Map();
for (const name of files) {
  const match = name.match(/^(\d+)_.*\.sql$/);
  if (!match) {
    fail(`migration filename does not begin with a numeric version: ${name}`);
    continue;
  }
  const prior = versions.get(match[1]);
  if (prior) fail(`duplicate migration version ${match[1]}: ${prior} and ${name}`);
  else versions.set(match[1], name);
}

function readMigration(name) {
  const fullPath = path.join(migrationsDir, name);
  if (!fs.existsSync(fullPath)) {
    fail(`required migration is missing: ${name}`);
    return "";
  }
  return fs.readFileSync(fullPath, "utf8");
}

function assertBefore(source, first, second, label) {
  const a = source.indexOf(first);
  const b = source.indexOf(second);
  if (a < 0) fail(`${label}: prerequisite statement not found: ${first}`);
  else if (b < 0) fail(`${label}: dependent statement not found: ${second}`);
  else if (a >= b) fail(`${label}: prerequisite must precede dependent statement`);
}

const lab = readMigration("20260912162001_hims_workflow_completion.sql");
assertBefore(
  lab,
  "ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0",
  "CREATE INDEX IF NOT EXISTS lab_test_parameters_test_idx",
  "legacy lab parameter ordering"
);

const queue = readMigration("20260911233000_phase2_service_order_payment_gating.sql");
assertBefore(
  queue,
  "ADD COLUMN IF NOT EXISTS queued_at",
  "CREATE INDEX IF NOT EXISTS idx_department_queues_work",
  "legacy department queue timestamp"
);

const transition = readMigration("20260920063000_insurance_claim_transition_state_hardening.sql");
if (!/\)\s*RETURNS\s+JSONB\b/i.test(transition)) {
  fail("insurance claim transition function must preserve its established JSONB return contract");
}

const claim = readMigration("20260920062000_insurance_claim_financial_bounds.sql");
if (!claim.includes("AS $claim_financials$") || !claim.includes("$claim_financials$;")) {
  fail("insurance claim financial function must use a matching named dollar-quote delimiter");
}
if (claim.includes("END; $;")) fail("insurance claim financial migration contains a bare dollar-quote terminator");

const reportSeed = readMigration("20260920211000_privileged_admin_resource_scope_hardening.sql");
if (!/CREATE OR REPLACE FUNCTION public\.seed_facility_reports\(_facility_id uuid\)\s+RETURNS integer\b/i.test(reportSeed)) {
  fail("facility report seeding must preserve its established INTEGER RPC return contract");
}
if (!/GET DIAGNOSTICS v_count = ROW_COUNT;\s+RETURN v_count;/i.test(reportSeed)) {
  fail("facility report seeding must return the affected row count");
}

const patientHubEntrypoints = readMigration("20260923130000_patient_hub_entrypoint_context_hardening.sql");
if (!/GRANT EXECUTE ON FUNCTION public\.record_patient_vitals\(UUID,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC\) TO authenticated/i.test(patientHubEntrypoints)) {
  fail("patient vitals grant must match the nine-argument RPC signature");
}
const facility = readMigration("20260930014000_clinical_facility_reconciliation_control_plane.sql");
const labResultBranch = facility.match(/elsif _entity_type='lab_results' then([\s\S]*?)elsif _entity_type='imaging_orders' then/i)?.[1] ?? "";
if (!labResultBranch) {
  fail("clinical facility reconciliation must retain a lab_results branch");
} else {
  if (/\br\.patient_id\b/i.test(labResultBranch)) {
    fail("lab_results reconciliation must not read patient_id from lab_results; derive it through the parent lab_orders row");
  }
  if (!/left join public\.lab_orders lo on lo\.id=r\.lab_order_id/i.test(labResultBranch) || !/\blo\.patient_id\b/i.test(labResultBranch)) {
    fail("lab_results reconciliation must derive patient lineage from the parent lab_orders row");
  }
}

if (process.exitCode) {
  process.exit(process.exitCode);
}
console.log(`Migration static contract passed (${files.length} SQL migrations checked for version uniqueness; targeted ordering and delimiter contracts passed).`);
