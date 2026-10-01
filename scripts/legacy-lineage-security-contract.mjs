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


const mutationMigration = fs.readFileSync(
  'supabase/migrations/20261001101500_harden_authenticated_clinical_mutation_boundaries.sql',
  'utf8',
);
for (const token of [
  'Appointment or patient belongs to a different facility context',
  'Bed or patient belongs to a different facility context',
  'Laboratory result belongs to a different facility context',
  'Medication administration belongs to a different facility context',
  'Medication prescription facility lineage is unresolved or mismatched',
  'REVOKE ALL ON FUNCTION public.claim_appointment(uuid) FROM PUBLIC,anon',
  'REVOKE ALL ON FUNCTION public.transition_medication_administration(uuid,text,text,text,uuid) FROM PUBLIC,anon',
]) {
  assert(mutationMigration.includes(token), `Missing mutation boundary: ${token}`);
}
console.log('Legacy lineage and clinical RPC security contract passed.');

