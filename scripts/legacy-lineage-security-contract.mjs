import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20261001094000_harden_legacy_lineage_and_clinical_rpc_boundaries.sql',
  'utf8',
);

const required = [
  'Patient facility attribution is unresolved; reconcile the patient before clinical documentation',
  'Patient facility attribution is unresolved; reconcile the patient before creating an encounter',
  'Patient facility attribution is unresolved; reconcile the patient before starting the appointment',
  'Handover facility attribution is unresolved',
  'Vital alert facility attribution is unresolved',
  'Patient facility attribution is unresolved',
  'Encounter facility attribution is unresolved',
  'Encounter or patient facility attribution is unresolved',
  'Parent clinical record has no facility attribution; reconcile the parent record first',
];

for (const token of required) {
  assert(migration.includes(token), `Missing lineage guard: ${token}`);
}

assert(
  !migration.includes('UPDATE public.patients SET facility_id=v_facility'),
  'Clinical workflow hardening must not silently assign unresolved patients to the caller facility',
);
assert(
  !migration.includes('UPDATE public.patients\n        SET facility_id = v_facility'),
  'Appointment start hardening must not silently assign unresolved patients',
);
assert(
  migration.includes('REVOKE ALL ON FUNCTION public.start_appointment_encounter(uuid,text,text) FROM PUBLIC,anon'),
  'Appointment encounter RPC must remain non-public',
);
assert(
  migration.includes('REVOKE ALL ON FUNCTION public.ensure_encounter_facility_attribution(uuid) FROM PUBLIC,anon'),
  'Encounter attribution helper must remain non-public',
);

console.log('Legacy lineage and clinical RPC security contract passed.');
