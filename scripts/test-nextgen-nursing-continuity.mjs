import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20260916195000_nextgen_nursing_continuity_integrity.sql';
const sql = fs.readFileSync(migrationPath, 'utf8');

const required = [
  'CREATE OR REPLACE FUNCTION public.create_nursing_care_plan',
  "_priority TEXT DEFAULT 'routine'",
  "_admission_id UUID DEFAULT NULL",
  "Care plans can only be created for an active admission",
  'CREATE OR REPLACE FUNCTION public.transition_nursing_care_plan',
  'SELECT * INTO v_plan FROM public.nursing_care_plans WHERE id = _plan_id FOR UPDATE',
  'Closed nursing care plans cannot be reopened',
  'A reason is required when a care plan is put on hold or cancelled',
  'Evaluation is required before completing a nursing care plan',
  'An active care plan cannot remain active after admission closure',
  'CREATE OR REPLACE FUNCTION public.create_nursing_shift_handover',
  'Handover must reference an active admission',
  'outgoing_officer, incoming_officer',
  'CREATE OR REPLACE FUNCTION public.acknowledge_nursing_shift_handover',
  'Only the designated incoming officer or an administrator can acknowledge this handover',
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

const closedStates = ['completed', 'cancelled'];
for (const state of closedStates) {
  if (!sql.includes(`v_plan.status IN ('completed','cancelled')`)) throw new Error(`Closed-state guard missing: ${state}`);
}

console.log('Next-gen nursing continuity integrity contract passed: admission linkage, row-locking, care-plan lifecycle, required evaluation/reasons, designated handover acknowledgement, and direct-write lockdown are present.');
