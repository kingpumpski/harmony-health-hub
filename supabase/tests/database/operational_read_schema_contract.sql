begin;

select plan(7);

select has_column(
  'public',
  'theatre_cases',
  'urgency',
  'theatre_cases.urgency must exist for Theatre Board operational reads'
);

select has_column(
  'public',
  'insurance_claims',
  'created_at',
  'insurance_claims.created_at must exist for Claims operational reads'
);

select has_column(
  'public',
  'insurance_claims',
  'updated_at',
  'insurance_claims.updated_at must exist for Claims operational writes'
);

select has_column(
  'public',
  'prescriptions',
  'computed_quantity',
  'prescriptions.computed_quantity must exist for Pharmacy reads'
);

select has_column(
  'public',
  'service_orders',
  'patient_id',
  'service_orders.patient_id must exist for patient relationship expansion'
);

select has_column(
  'public',
  'prescriptions',
  'patient_id',
  'prescriptions.patient_id must exist for patient relationship expansion'
);

select has_column(
  'public',
  'theatre_cases',
  'patient_id',
  'theatre_cases.patient_id must exist for patient relationship expansion'
);

select * from finish();

rollback;
