import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260916190000_nextgen_theatre_emergency_integrity.sql','utf8');

const checks = [
  ['theatre create workflow', /CREATE OR REPLACE FUNCTION public\.create_theatre_case\(/],
  ['canonical theatre scheduled_start column', /scheduled_start/],
  ['canonical theatre theatre_name column', /theatre_name/],
  ['theatre encounter ownership', /v_patient<>_patient_id/],
  ['theatre advisory concurrency lock', /pg_advisory_xact_lock/],
  ['theatre duplicate active-start guard', /Conflicting active theatre case/],
  ['theatre row lock', /FROM public\.theatre_cases WHERE id=_case_id FOR UPDATE/],
  ['theatre explicit transition matrix', /WHEN 'requested' THEN _status IN/],
  ['theatre closed-state protection', /WHEN 'completed' THEN _status='completed'/],
  ['theatre cancellation/postponement reason', /Reason is required when cancelling or postponing/],
  ['theatre encounter closure protection', /Cannot progress theatre case for a completed encounter/],
  ['emergency transition workflow', /CREATE OR REPLACE FUNCTION public\.transition_emergency_case\(/],
  ['emergency row lock', /FROM public\.emergency_cases WHERE id=_case_id FOR UPDATE/],
  ['emergency explicit transition matrix', /WHEN 'waiting' THEN _status IN/],
  ['emergency terminal disposition', /Disposition is required for terminal emergency outcome/],
  ['emergency disposition timestamp', /disposition_at=CASE WHEN _status IN/],
  ['public execute isolation', /REVOKE ALL ON FUNCTION public\.transition_emergency_case/],
  ['authenticated execute grant', /GRANT EXECUTE ON FUNCTION public\.transition_theatre_case/],
];

for (const [label, pattern] of checks) {
  if (!pattern.test(migration)) throw new Error(`Missing theatre/emergency safety contract: ${label}`);
}
console.log(`nextgen theatre/emergency contracts passed (${checks.length} checks)`);
