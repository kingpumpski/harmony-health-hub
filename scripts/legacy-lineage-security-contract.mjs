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

const acuteMigration = fs.readFileSync(
  'supabase/migrations/20261001113000_harden_acute_clinical_facility_lineage.sql',
  'utf8',
);
for (const token of [
  'public.enforce_clinical_facility_lineage()',
  'public.enforce_ai_clinical_event_facility()',
  'trg_enforce_imaging_facility_lineage',
  'trg_enforce_emergency_facility_lineage',
  'trg_enforce_theatre_facility_lineage',
  'trg_enforce_transfusion_facility_lineage',
  'trg_enforce_admission_facility_lineage',
  'trg_enforce_ai_session_facility_lineage',
  'trg_enforce_ai_event_facility_lineage',
  'Clinical record facility does not match patient facility',
  'Patient facility attribution is unresolved',
  'AI clinical event belongs to a different facility context',
  'REVOKE ALL ON FUNCTION public.enforce_clinical_facility_lineage() FROM PUBLIC,anon',
]) {
  assert(acuteMigration.includes(token), `Missing acute clinical lineage guard: ${token}`);
}

const wrapperMigration = fs.readFileSync(
  'supabase/migrations/20261001123000_harden_legacy_clinical_wrapper_facility_context.sql',
  'utf8',
);
for (const token of [
  'CREATE OR REPLACE FUNCTION public.get_pending_specialist_referrals()',
  'CREATE OR REPLACE FUNCTION public.patient_coverage_details(_patient_id uuid)',
  'Patient facility attribution is unresolved',
  'Patient belongs to a different facility context',
  'REVOKE ALL ON FUNCTION public.get_pending_specialist_referrals() FROM PUBLIC,anon',
  'REVOKE ALL ON FUNCTION public.patient_coverage_details(uuid) FROM PUBLIC,anon',
]) {
  assert(wrapperMigration.includes(token), `Missing legacy wrapper boundary: ${token}`);
}

const patientReadMigration = fs.readFileSync(
  'supabase/migrations/20261001140000_harden_patient_read_facility_context.sql',
  'utf8',
);
for (const token of [
  'CREATE OR REPLACE FUNCTION public.assert_patient_facility_context(_patient_id uuid)',
  'Patient facility attribution is unresolved',
  'Patient belongs to a different facility context',
  'CREATE OR REPLACE FUNCTION public.get_patient_hub_clinical_snapshot(_patient_id uuid)',
  'CREATE OR REPLACE FUNCTION public.get_patient_current_treatment_snapshot(_patient_id uuid,_admission_id uuid)',
  'REVOKE ALL ON FUNCTION public.assert_patient_facility_context(uuid) FROM PUBLIC,anon,authenticated',
]) {
  assert(patientReadMigration.includes(token), `Missing patient read facility boundary: ${token}`);
}

const acuteMutationMigration = fs.readFileSync(
  'supabase/migrations/20261001141000_harden_admission_and_imaging_facility_context.sql',
  'utf8',
);
for (const token of [
  'CREATE OR REPLACE FUNCTION public.create_admission_workflow(_patient_id uuid,_ward text',
  'INSERT INTO public.admissions(patient_id,ward,bed,reason,admitted_by,status,admitted_at,facility_id)',
  'CREATE OR REPLACE FUNCTION public.create_imaging_order_with_payment_gate(_patient_id uuid',
  'INSERT INTO public.imaging_orders(patient_id,encounter_id,modality,study_name,body_site,priority,clinical_indication,amount,status,requested_by,facility_id)',
  'Patient belongs to a different facility context',
  'REVOKE ALL ON FUNCTION public.create_admission_workflow(uuid,text,text,text) FROM PUBLIC,anon',
  'REVOKE ALL ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) FROM PUBLIC,anon',
]) {
  assert(acuteMutationMigration.includes(token), `Missing admission/imaging facility boundary: ${token}`);
}

const clinicalAiMigration = fs.readFileSync(
  'supabase/migrations/20261001143000_harden_patient_clinical_ai_billing_context.sql',
  'utf8',
);
for (const token of [
  'CREATE OR REPLACE FUNCTION public.create_appointment_workflow(_patient_id uuid',
  'CREATE OR REPLACE FUNCTION public.create_ai_clinical_session(_patient_id uuid',
  'CREATE OR REPLACE FUNCTION public.get_ai_clinical_context(_patient_id uuid)',
  'CREATE OR REPLACE FUNCTION public.get_attending_patient_history(_patient_id uuid',
  'CREATE OR REPLACE FUNCTION public.get_billing_window(_patient_id uuid',
  'CREATE OR REPLACE FUNCTION public.create_patient_document(_patient_id uuid',
  'CREATE OR REPLACE FUNCTION public.create_encounter_prescription(_encounter_id uuid',
  'PERFORM public.assert_patient_facility_context',
  'REVOKE ALL ON FUNCTION public.get_ai_clinical_context(uuid) FROM PUBLIC,anon',
]) {
  assert(clinicalAiMigration.includes(token), `Missing patient clinical AI boundary: ${token}`);
}

const appointmentStartMigration = fs.readFileSync(
  'supabase/migrations/20261001150000_harden_start_appointment_encounter_facility_context.sql',
  'utf8',
);
for (const token of [
  'SET search_path = pg_catalog, public',
  'v_is_privileged boolean := public.has_role(v_user, \'admin\'::public.app_role) OR public.has_role(v_user, \'it_admin\'::public.app_role)',
  'Patient facility attribution is unresolved; reconcile the patient before starting the appointment',
  'Appointment belongs to a different facility context',
  'Encounter patient does not match appointment patient',
  'REVOKE ALL ON FUNCTION public.start_appointment_encounter(uuid,text,text) FROM PUBLIC, anon',
  'GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(uuid,text,text) TO authenticated',
]) {
  assert(appointmentStartMigration.includes(token), `Missing appointment-start boundary: ${token}`);
}


const encounterImagingMigration = fs.readFileSync(
  'supabase/migrations/20261001151500_harden_encounter_submit_imaging_facility_context.sql',
  'utf8',
);
for (const token of [
  'v_patient_facility := public.assert_patient_facility_context(v_enc.patient_id)',
  'Encounter facility attribution is unresolved',
  'Encounter or patient belongs to a different facility context',
  'facility_id',
  'Imaging order facility attribution is unresolved',
  'Imaging order belongs to a different facility context',
  'Imaging service order linkage or facility context is invalid',
  'REVOKE ALL ON FUNCTION public.submit_encounter_workflow(uuid,text,timestamptz,text) FROM PUBLIC, anon',
  'REVOKE ALL ON FUNCTION public.start_imaging_order(uuid) FROM PUBLIC, anon',
  'REVOKE ALL ON FUNCTION public.complete_imaging_order(uuid,text,text) FROM PUBLIC, anon',
]) {
  assert(encounterImagingMigration.includes(token), `Missing encounter/imaging facility boundary: ${token}`);
}


const serviceOrderMigration = fs.readFileSync(
  'supabase/migrations/20261001145619_harden_service_order_patient_encounter_facility_lineage.sql',
  'utf8',
);
for (const token of [
  'CREATE OR REPLACE FUNCTION public.validate_service_order_encounter()',
  'Patient facility attribution is unresolved; reconcile the patient before creating a service order',
  'Encounter facility attribution is unresolved; reconcile the encounter before creating a service order',
  'Service order, encounter, and patient facility lineage must match',
  'REVOKE ALL ON FUNCTION public.validate_service_order_encounter() FROM PUBLIC, anon, authenticated',
  "tgname = 'service_order_encounter_guard'",
]) {
  assert(serviceOrderMigration.includes(token), `Missing service-order facility boundary: ${token}`);
}


const outsideLabMigration = fs.readFileSync(
  'supabase/migrations/20261001151540_harden_outside_lab_document_facility_context.sql',
  'utf8',
);
for (const token of [
  'CREATE OR REPLACE FUNCTION public.register_outside_lab_document',
  'public.assert_patient_facility_context(_patient_id)',
  'outside_lab_documents(patient_id,facility_id,document_type,title,storage_path,mime_type,uploaded_by)',
  'Storage path must be scoped to the patient',
  'CREATE OR REPLACE FUNCTION public.complete_outside_lab_ai_analysis',
  'Outside-lab document facility lineage is unresolved or inconsistent',
  'REVOKE ALL ON FUNCTION public.register_outside_lab_document(uuid,text,text,text,text) FROM PUBLIC, anon',
  'REVOKE ALL ON FUNCTION public.complete_outside_lab_ai_analysis(uuid,text) FROM PUBLIC, anon',
]) {
  assert(outsideLabMigration.includes(token), `Missing outside-lab facility boundary: ${token}`);
}

const insuranceClaimMigration = fs.readFileSync(
  'supabase/migrations/20261001151542_harden_insurance_claim_facility_context.sql',
  'utf8',
);
for (const token of [
  'CREATE OR REPLACE FUNCTION public.create_insurance_claim_draft',
  'v_facility := public.assert_patient_facility_context(_patient_id)',
  'i.patient_id=_patient_id AND i.facility_id=v_facility',
  'INSERT INTO public.insurance_claims(invoice_id,patient_id,facility_id',
  'insurance_claim_draft_created',
  'REVOKE ALL ON FUNCTION public.create_insurance_claim_draft(uuid,text,text,numeric,uuid) FROM PUBLIC, anon',
  'GRANT EXECUTE ON FUNCTION public.create_insurance_claim_draft(uuid,text,text,numeric,uuid) TO authenticated',
]) {
  assert(insuranceClaimMigration.includes(token), `Missing insurance-claim facility boundary: ${token}`);
}


const internalTriggerMigration = fs.readFileSync(
  'supabase/migrations/20261001152358_lock_internal_trigger_function_execute_grants.sql',
  'utf8',
);
for (const token of [
  'REVOKE ALL ON FUNCTION public.calculate_triage_bmi() FROM PUBLIC, anon, authenticated, service_role',
  'REVOKE ALL ON FUNCTION public.enforce_clinical_facility_lineage() FROM PUBLIC, anon, authenticated, service_role',
  'REVOKE ALL ON FUNCTION public.prevent_notification_audit_mutation() FROM PUBLIC, anon, authenticated, service_role',
  'REVOKE ALL ON FUNCTION public.validate_service_order_encounter() FROM PUBLIC, anon, authenticated, service_role',
  "has_function_privilege('authenticated', v_function.signature, 'EXECUTE')",
  'Internal trigger function remains directly executable',
]) {
  assert(internalTriggerMigration.includes(token), `Missing internal trigger privilege boundary: ${token}`);
}


const pharmacyCareMigration = fs.readFileSync(
  'supabase/migrations/20261001152608_harden_pharmacy_care_transition_document_boundaries.sql',
  'utf8',
);
for (const token of [
  'CREATE OR REPLACE FUNCTION public.prepare_pharmacy_dispensing',
  'public.assert_patient_facility_context(p.patient_id)',
  'CREATE OR REPLACE FUNCTION public.confirm_pharmacy_dispense',
  'CREATE OR REPLACE FUNCTION public.create_care_transition_workflow',
  'CREATE OR REPLACE FUNCTION public.upload_patient_document_metadata',
  'Storage path must be scoped to the patient',
  'REVOKE ALL ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) FROM PUBLIC,anon',
]) {
  assert(pharmacyCareMigration.includes(token), `Missing pharmacy/care-transition/document boundary: ${token}`);
}

const pharmacyPosMigration = fs.readFileSync(
  'supabase/migrations/20261001152610_harden_pharmacy_pos_facility_context.sql',
  'utf8',
);
for (const token of [
  'CREATE OR REPLACE FUNCTION public.create_pharmacy_pos_sale',
  'public.assert_patient_facility_context(_patient_id)',
  'CREATE OR REPLACE FUNCTION public.confirm_pharmacy_pos_sale',
  'POS sale facility attribution is unresolved or mismatched',
  'REVOKE ALL ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) FROM PUBLIC,anon',
]) {
  assert(pharmacyPosMigration.includes(token), `Missing pharmacy POS facility boundary: ${token}`);
}

console.log('Legacy lineage and clinical RPC security contract passed.');