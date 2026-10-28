BEGIN;

SELECT plan(16);

SELECT has_column('public', 'department_queues', 'queued_at',
  'department queue ordering timestamp exists before index use');
SELECT has_column('public', 'lab_test_parameters', 'sort_order',
  'legacy laboratory parameters support stable ordering');
SELECT has_table('public', 'patient_audit_log',
  'patient audit retention target exists in the clean schema');
SELECT has_column('public', 'insurance_claims', 'payer_name',
  'insurance claims expose canonical payer name');
SELECT has_column('public', 'insurance_claims', 'member_number',
  'insurance claims expose canonical member number');
SELECT has_column('public', 'insurance_claims', 'amount_paid',
  'insurance claims expose paid amount');
SELECT has_column('public', 'insurance_claims', 'created_at',
  'insurance claims expose creation timestamp');
SELECT has_column('public', 'insurance_claims', 'updated_at',
  'insurance claims expose update timestamp');
SELECT has_column('public', 'nursing_care_plans', 'encounter_id',
  'nursing care plans can link to encounters');
SELECT has_column('public', 'nursing_shift_handovers', 'shift_label',
  'nursing handovers expose canonical shift label');
SELECT has_column('public', 'emergency_cases', 'arrival_time',
  'emergency cases expose canonical arrival time');
SELECT has_column('public', 'emergency_cases', 'acuity',
  'emergency cases expose canonical acuity');
SELECT has_column('public', 'theatre_cases', 'scheduled_start',
  'theatre cases expose canonical scheduled start');
SELECT has_column('public', 'transfusion_records', 'blood_product',
  'transfusion records expose canonical blood product');
SELECT ok(
  to_regprocedure('public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)') IS NOT NULL
  AND pg_get_function_result(to_regprocedure('public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)')) = 'jsonb',
  'insurance claim financial RPC preserves its JSONB return contract'
);
SELECT ok(
  to_regprocedure('public.transition_medication_administration(uuid,text,text,text,uuid)') IS NOT NULL
  AND pg_get_function_result(to_regprocedure('public.transition_medication_administration(uuid,text,text,text,uuid)')) = 'uuid',
  'medication administration transition RPC preserves its UUID return contract'
);

SELECT * FROM finish();
ROLLBACK;
