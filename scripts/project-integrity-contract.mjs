import fs from "node:fs";

const read = (file) => fs.readFileSync(file, "utf8");
const fail = (message) => {
  console.error(`[project-integrity] FAIL: ${message}`);
  process.exitCode = 1;
};

const evidence = JSON.parse(read("scripts/authorization-isolation-evidence.json"));
if (evidence.environment !== "not_configured" || evidence.status !== "not_run") {
  fail("deferred two-facility isolation must remain unconfigured/not_run until an isolated regression environment produces complete evidence");
}

const tenancy = read("supabase/migrations/20260929160000_patient_facility_tenancy_foundation.sql");
if (!tenancy.includes("Do not apply this migration to production")) {
  fail("patient/facility tenancy foundation must retain its explicit non-production gate");
}
if (/ALTER TABLE public\.patients\s+ENABLE ROW LEVEL SECURITY/i.test(tenancy)) {
  fail("tenancy foundation must not enable patient-table RLS before isolated cross-facility evidence exists");
}
if (/CREATE POLICY[^;]+ON public\.patients/i.test(tenancy)) {
  fail("tenancy foundation must not add patient-table policies before isolated cross-facility evidence exists");
}

const encounter = read("supabase/migrations/20260930020000_encounter_draft_edit_workflow.sql");
for (const token of [
  "FOR UPDATE",
  "status IN ('completed', 'cancelled')",
  "GRANT EXECUTE ON FUNCTION public.update_encounter_draft_workflow",
  "REVOKE ALL ON FUNCTION public.update_encounter_draft_workflow"
]) {
  if (!encounter.includes(token)) fail(`encounter draft workflow integrity guard missing: ${token}`);
}

const hub = read("src/pages/patients/PatientHub.tsx");
if (!hub.includes("rpc('create_encounter_workflow'")) fail("Patient Hub must create encounters through the canonical RPC");
if (/from\(['"]encounters['"]\)\.insert/.test(hub)) fail("Patient Hub must not directly insert encounter rows");

console.log("[project-integrity] deferred tenancy, encounter workflow, and Patient Hub authorization gates are intact");
