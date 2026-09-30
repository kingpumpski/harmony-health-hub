import fs from "node:fs";

const read = (file) => fs.readFileSync(file, "utf8");
const fail = (message) => {
  console.error(`[project-integrity] FAIL: ${message}`);
  process.exitCode = 1;
};

const facilityContext = read("supabase/migrations/20260930012647_canonical_clinical_facility_reconciliation_control_plane.sql");
const facilityCleanup = read("supabase/migrations/20260930013529_remove_abandoned_clinical_facility_reconciliation.sql");
for (const token of ["get_user_facilities", "get_current_facility_context", "set_active_facility_context", "ensure_encounter_facility_attribution", "INSERT INTO public.encounters(patient_id,facility_id"]) {
  if (!facilityContext.includes(token)) fail(`facility-context integrity guard missing: ${token}`);
}
if (!facilityCleanup.includes("DROP TABLE IF EXISTS public.clinical_facility_reconciliation")) fail("deferred facility reconciliation cleanup must remain versioned");

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

console.log("[project-integrity] encounter workflow and Patient Hub authorization gates are intact");
