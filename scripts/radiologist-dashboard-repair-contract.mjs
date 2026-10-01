import fs from 'node:fs';

const migration=fs.readFileSync('supabase/migrations/20261001101200_repair_radiologist_dashboard_aggregation.sql','utf8');
const source=fs.readFileSync('supabase/migrations/20260929190000_role_dashboard_radiologist_workflow_boundary.sql','utf8');

for (const needle of [
  "public.get_role_dashboard_summary()'::regprocedure",
  "public.get_role_dashboard_summary_for_role(text)'::regprocedure",
  "position(v_old IN v_definition) = 0",
  "Radiologist dashboard branch is missing",
  "RAISE EXCEPTION 'Radiologist dashboard branch in % has unexpected SQL shape; refusing silent patch'",
  "REVOKE ALL ON FUNCTION public.get_role_dashboard_summary() FROM PUBLIC, anon",
  "REVOKE ALL ON FUNCTION public.get_role_dashboard_summary_for_role(text) FROM PUBLIC, anon",
  "GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary() TO authenticated",
  "GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary_for_role(text) TO authenticated"
]) {
  if (!migration.includes(needle)) throw new Error("Radiologist repair migration missing guard: " + needle);
}

for (const needle of [
  "ELSIF v_role = 'radiologist'",
  "Ready for interpretation",
  "Urgent / STAT",
  "public.imaging_orders"
]) {
  if (!source.includes(needle)) throw new Error("Canonical radiologist dashboard source missing: " + needle);
}

console.log('Radiologist dashboard blocker-prevention contract passed');
