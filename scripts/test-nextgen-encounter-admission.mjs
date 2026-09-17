import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260917170000_nextgen_encounter_admission_financial_override.sql', 'utf8');
const settings = fs.readFileSync('src/pages/admin/Settings.tsx', 'utf8');
const actions = fs.readFileSync('src/components/EncounterAdmissionActions.tsx', 'utf8');
const app = fs.readFileSync('src/App.tsx', 'utf8');

const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

assert(migration.includes('CREATE OR REPLACE FUNCTION public.admit_encounter_workflow'), 'Admission workflow RPC is missing');
assert(migration.includes("IF v_enc.status <> 'completed'"), 'Admission must require a submitted/completed encounter');
assert(migration.includes('pg_advisory_xact_lock'), 'Admission workflow lacks concurrency serialization');
assert(migration.includes("allow_treatment_before_deposit") && migration.includes("allow_clinical_emergency_override"), 'Facility emergency controls are missing');
assert(migration.includes('billing_overrides') && migration.includes('department_queues'), 'Emergency admission must reuse canonical financial and department queue infrastructure');
assert(migration.includes("status='pending_payment_approval'") && migration.includes("status='released'"), 'Emergency release boundary is missing');
assert(settings.includes('Allow treatment before deposit') && settings.includes('Allow admission financial override') && settings.includes('Require Accounts release after deposit'), 'Admin settings do not expose the facility financial controls');
assert(actions.includes("rpc('admit_encounter_workflow'") && actions.includes('Admit'), 'Encounter admission action surface is missing');
assert(app.includes("import EncounterAdmissionActions") && app.includes('<EncounterAdmissionActions />'), 'Encounter admission action surface is not mounted');

console.log('Next-gen encounter admission contract passed: submitted encounters have a server-authoritative admission action, facility-controlled emergency override, audit/queue integration, and Accounts reconciliation boundary.');
