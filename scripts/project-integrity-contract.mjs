import fs from "node:fs";

const read = (file) => fs.readFileSync(file, "utf8");
const fail = (message) => {
  console.error(`[project-integrity] FAIL: ${message}`);
  process.exitCode = 1;
};

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
