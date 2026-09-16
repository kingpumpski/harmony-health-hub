import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20260916195000_nextgen_nursing_continuity_integrity.sql';
const dateMigrationPath = 'supabase/migrations/20260916200000_nextgen_nursing_handover_date_integrity.sql';
const canonicalWorkflowPath = 'supabase/migrations/20260912033000_global_hims_reconciliation_hardening.sql';
const pagePath = 'src/pages/NursingHandover.tsx';
const sql = fs.readFileSync(migrationPath, 'utf8');
const dateSql = fs.readFileSync(dateMigrationPath, 'utf8');
const canonicalWorkflow = fs.readFileSync(canonicalWorkflowPath, 'utf8');
const page = fs.readFileSync(pagePath, 'utf8');

const required = [
  'ALTER TABLE public.nursing_shift_handovers',
  'ADD COLUMN IF NOT EXISTS admission_id UUID',
  'nursing_shift_handovers_admission_id_fkey',
  'idx_nursing_handover_admission',
  'CREATE OR REPLACE FUNCTION public.create_nursing_care_plan',
  "_priority TEXT DEFAULT 'routine'",
  "_admission_id UUID DEFAULT NULL",
  'Care plans can only be created for an active admission',
  'CREATE OR REPLACE FUNCTION public.transition_nursing_care_plan',
  'SELECT * INTO v_plan FROM public.nursing_care_plans WHERE id = _plan_id FOR UPDATE',
  'Closed nursing care plans cannot be reopened',
  'A reason is required when a care plan is put on hold or cancelled',
  'Evaluation is required before completing a nursing care plan',
  'An active care plan cannot remain active after admission closure',
  'CREATE OR REPLACE FUNCTION public.create_nursing_shift_handover',
  'Preserve the established seven-argument handover function exactly as the',
  'Handover must reference an active admission',
  'patient_id, admission_id, outgoing_officer, incoming_officer, shift_label',
  'clinical_summary, pending_tasks, safety_concerns, escalation_required',
  'CREATE OR REPLACE FUNCTION public.acknowledge_nursing_shift_handover',
  'Only the designated incoming officer or an administrator can acknowledge this handover',
  'Incoming officer must hold an authorized nursing role',
  'FOR UPDATE',
  'REVOKE INSERT, UPDATE, DELETE ON public.nursing_care_plans FROM authenticated',
  'REVOKE INSERT, UPDATE, DELETE ON public.nursing_shift_handovers FROM authenticated',
  'GRANT EXECUTE ON FUNCTION public.create_nursing_care_plan',
  'GRANT EXECUTE ON FUNCTION public.transition_nursing_care_plan',
  'GRANT EXECUTE ON FUNCTION public.create_nursing_shift_handover',
  'GRANT EXECUTE ON FUNCTION public.acknowledge_nursing_shift_handover',
];
for (const token of required) {
  if (!sql.includes(token)) throw new Error(`Nursing continuity control missing: ${token}`);
}

const canonicalSignature = 'create_nursing_shift_handover(\n  _patient_id UUID,\n  _shift_label TEXT,\n  _clinical_summary TEXT,\n  _pending_tasks TEXT DEFAULT NULL,\n  _safety_concerns TEXT DEFAULT NULL,\n  _escalation_required BOOLEAN DEFAULT FALSE,\n  _ward_id UUID DEFAULT NULL';
if (!canonicalWorkflow.includes(canonicalSignature)) throw new Error('Canonical seven-argument nursing handover signature is missing');

const dateRequired = [
  'ALTER TABLE public.nursing_shift_handovers',
  'ADD COLUMN IF NOT EXISTS shift_date DATE NOT NULL DEFAULT CURRENT_DATE',
  'idx_nursing_handover_admission_shift_date',
  '_shift_date DATE',
  "_shift_date > CURRENT_DATE + 1 OR _shift_date < CURRENT_DATE - 1",
  'shift_date,\n    shift_label',
  '_shift_date, btrim(_shift_name)',
  'Clinical shift date supplied by the handover workflow',
];
for (const token of dateRequired) {
  if (!dateSql.includes(token)) throw new Error(`Nursing handover date persistence control missing: ${token}`);
}

if (!sql.includes("v_admission_status <> 'admitted'")) throw new Error('Admission active-state reconciliation missing');
if (!sql.includes("v_status <> 'admitted'")) throw new Error('Handover admission active-state reconciliation missing');
if (!sql.includes("v_plan.status IN ('completed','cancelled')")) throw new Error('Closed-state guard missing');

const pageRequired = [
  ['handover UI loads active admissions', /from\('admissions'\)\.select\('id,patient_id,status,discharged_at'\)\.eq\('status','admitted'\)\.is\('discharged_at',null\)/],
  ['handover UI builds admission map', /admissionMap\[admission\.patient_id\]=admission\.id/],
  ['handover UI uses admission-aware RPC', /_admission_id:admissionId/],
  ['handover UI sends shift date', /_shift_date:shiftDate/],
  ['handover UI uses next-gen acknowledgement RPC', /acknowledge_nursing_shift_handover/],
  ['handover UI blocks non-admitted patients', /Active admission required/],
  ['handover UI only offers admitted patients', /patients\.filter\(p=>Boolean\(activeAdmissions\[p\.id\]\)\)/],
];
for (const [label, pattern] of pageRequired) {
  if (!pattern.test(page)) throw new Error(`Nursing UI continuity contract missing: ${label}`);
}

console.log('Next-gen nursing continuity integrity contract passed: canonical schema reconciliation, preserved legacy handover signature, persisted shift-date semantics, admission-linked UI/RPC workflow, row-locking, care-plan lifecycle, designated acknowledgement, role validation, and direct-write lockdown are present.');
