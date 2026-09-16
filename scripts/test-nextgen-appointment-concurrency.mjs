import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260916170000_nextgen_appointment_concurrency_workflow.sql', 'utf8');
const lockdown = fs.readFileSync('supabase/migrations/20260914143000_appointment_direct_write_lockdown.sql', 'utf8');
const audit = fs.readFileSync('supabase/migrations/20260916103000_nextgen_clinical_audit_convergence.sql', 'utf8');

const required = [
  ['server-authoritative create RPC', 'CREATE OR REPLACE FUNCTION public.create_appointment_workflow'],
  ['patient validation', "status <> 'merged'"],
  ['concurrent create serialization', 'pg_advisory_xact_lock'],
  ['duplicate appointment guard', 'An active appointment already exists for this patient and time'],
  ['server-authoritative claim RPC', 'CREATE OR REPLACE FUNCTION public.claim_appointment'],
  ['atomic claim ownership predicate', '(attending_officer_id IS NULL OR attending_officer_id = auth.uid())'],
  ['closed claim protection', "NOT IN ('completed','cancelled','no_show')"],
  ['row-locked appointment update', 'FROM public.appointments\n  WHERE id = _appointment_id\n  FOR UPDATE'],
  ['front-desk clinical boundary', 'Front desk cannot perform clinical treatment-state transitions'],
  ['assigned clinician boundary', 'Appointment must be claimed by this clinical officer'],
  ['scheduled-to-claimed boundary', 'Appointment must be claimed before clinical treatment begins'],
  ['claimed-to-start boundary', 'Claimed appointments may only start, cancel, or become no-show'],
  ['in-progress boundary', 'In-progress appointments may only continue or complete'],
  ['closed appointment update protection', 'Closed appointments cannot be modified'],
  ['encounter row lock', 'SELECT * INTO appt FROM public.appointments WHERE id = _appointment_id FOR UPDATE'],
  ['encounter claim requirement', 'Appointment must be claimed before starting the encounter'],
  ['closed encounter protection', 'Closed appointments cannot start a new encounter'],
  ['authenticated create execution', 'GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated'],
  ['authenticated claim execution', 'GRANT EXECUTE ON FUNCTION public.claim_appointment(UUID) TO authenticated'],
  ['authenticated update execution', 'GRANT EXECUTE ON FUNCTION public.update_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,TEXT) TO authenticated'],
  ['authenticated encounter execution', 'GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(UUID,TEXT,TEXT) TO authenticated'],
];

for (const [label, needle] of required) {
  if (!migration.includes(needle)) throw new Error(`Missing ${label}: ${needle}`);
}

for (const needle of [
  'REVOKE INSERT, UPDATE, DELETE ON public.appointments FROM authenticated',
  'REVOKE ALL ON FUNCTION public.claim_appointment(uuid) FROM PUBLIC, anon',
  'GRANT EXECUTE ON FUNCTION public.claim_appointment(uuid) TO authenticated',
]) if (!lockdown.includes(needle)) throw new Error(`Appointment direct-write lockdown missing: ${needle}`);

if (!audit.includes("'appointments'")) throw new Error('Appointment audit convergence missing');
if (!audit.includes('audit_clinical_record_change')) throw new Error('Canonical clinical audit boundary missing');

console.log('next-gen appointment concurrency and state-transition contract checks passed');
