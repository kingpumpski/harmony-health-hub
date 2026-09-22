import fs from 'node:fs';

const p = fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts', 'utf8');

const forbidden = [
  "from('medication_administrations').select('*')",
  "from('nursing_shift_handovers').select('*')",
  "from('triage_assessments').select('*')",
  "from('department_queues').select('*')",
];

for (const x of forbidden) {
  if (p.includes(x)) throw new Error(`nurse dashboard broad read remains: ${x}`);
}

const required = [
  "from('medication_administrations').select('id,patient_id,prescription_id,medication_name,dose,route,scheduled_at,administered_at,status,reason,administered_by,witnessed_by,notes,due_window_minutes,locked_at,lock_reason,reopened_at,reopen_reason,created_at,updated_at')",
  "from('nursing_shift_handovers').select('id,patient_id,admission_id,outgoing_officer,incoming_officer,shift_date,shift_name,clinical_summary,outstanding_tasks,risks_and_alerts,escalation_required,acknowledged_at,created_at,pending_tasks,safety_concerns,shift_label')",
  "from('triage_assessments').select('id,patient_id,recorded_by,systolic,diastolic,heart_rate,temperature,respiratory_rate,oxygen_saturation,weight_kg,height_m,pain_score,consciousness,presenting_complaint,clinical_notes,priority,is_critical,created_at,updated_at,bmi')",
  "from('department_queues').select('id,patient_id,department,status,priority,reason,related_encounter_id,related_invoice_id,payment_required,payment_satisfied,assigned_to,created_at,updated_at,completed_at,service_order_id,queued_at,claimed_by,claimed_at')",
];

for (const x of required) {
  if (!p.includes(x)) throw new Error(`expected explicit nurse dashboard projection missing: ${x}`);
}

if (p.includes(".from('profiles').select('id,first_name,last_name,department')")) {
  throw new Error('stale profiles role/projection read remains in clinical Edge Function');
}

console.log('Nurse dashboard Edge read-boundary contract passed');
