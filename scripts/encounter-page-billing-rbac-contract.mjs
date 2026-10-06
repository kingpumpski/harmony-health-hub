#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
const appointments=fs.readFileSync('src/pages/Appointments.tsx','utf8');
const encounters=fs.readFileSync('src/pages/Encounters.tsx','utf8');
const app=fs.readFileSync('src/App.tsx','utf8');
const billing=fs.readFileSync('supabase/migrations/20261006170000_reconcile_encounter_completion_billing_materialization.sql','utf8');
assert(app.includes('path="/encounters/:encounterId"'), 'canonical encounter document route must exist');
assert(appointments.includes('navigate(encounterId ?'), 'Start Encounter must navigate directly to the canonical encounter route');
assert(encounters.includes('const { encounterId: routeEncounterId } = useParams'), 'encounter page must consume the route encounter id');
assert(encounters.includes('const isStandaloneEncounter = Boolean(routeEncounterId)'), 'canonical encounter route must render as a standalone page');
assert(encounters.includes('principalDiagnosis = diagnoses.find((diagnosis) => diagnosis.is_principal)'), 'prescribing must resolve the principal diagnosis from the diagnosis section');
assert(!encounters.includes('Select diagnosis being treated'), 'prescribing must not render the redundant diagnosis selector');
assert(billing.includes('prepare_patient_billable_items(v_enc.patient_id'), 'encounter completion must materialize billing');
assert(billing.includes('Billing materialization is limited to the clinician'), 'clinical billing materialization must remain limited to the assigned clinician encounter');
assert(app.includes("const laboratoryWorkspaceRoles = ['admin', 'lab_technician']"), 'clinicians must not receive laboratory operator access');
assert(app.includes("const radiologyWorkspaceRoles = ['admin', 'radiologist', 'radiology_technician']"), 'clinicians must not receive radiology operator access');
console.log('Encounter page, direct-start, principal-diagnosis, billing materialization and RBAC contract passed.');
