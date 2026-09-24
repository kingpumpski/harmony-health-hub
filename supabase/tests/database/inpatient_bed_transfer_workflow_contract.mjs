import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260924232338_inpatient_transfer_movement_integrity.sql',
  'utf8',
);

const required = [
  "CREATE OR REPLACE FUNCTION public.transfer_patient_ward_bed_workflow(",
  "PERFORM pg_advisory_xact_lock(pg_catalog.hashtextextended(_patient_id::text, 0))",
  "FROM public.admissions",
  "FOR UPDATE",
  "v_admission.status <> 'admitted'",
  "FROM public.ward_beds",
  "v_destination.status <> 'available'",
  "v_destination.patient_id IS NOT NULL",
  "v_destination.admission_id IS NOT NULL",
  "status = 'occupied'",
  "status = 'cleaning'",
  "UPDATE public.ward_beds",
  "INSERT INTO public.care_transitions",
  "transition_type,",
  "'transfer'",
  "completed_at",
  "public.record_system_audit",
  "REVOKE ALL ON FUNCTION public.transfer_patient_ward_bed_workflow(UUID,UUID,UUID,UUID,TEXT,TEXT) FROM PUBLIC, anon",
  "GRANT EXECUTE ON FUNCTION public.transfer_patient_ward_bed_workflow(UUID,UUID,UUID,UUID,TEXT,TEXT) TO authenticated",
];

for (const fragment of required) {
  if (!migration.includes(fragment)) {
    throw new Error(`Missing inpatient bed transfer contract fragment: ${fragment}`);
  }
}

if (!/UPDATE public\.ward_beds[\s\S]*patient_id = NULL[\s\S]*admission_id = NULL[\s\S]*status = 'available'/.test(migration)) {
  throw new Error('Source bed is not released atomically to available state during transfer');
}

if (!/UPDATE public\.ward_beds[\s\S]*patient_id = _patient_id[\s\S]*admission_id = _admission_id[\s\S]*status = 'occupied'/.test(migration)) {
  throw new Error('Target bed is not atomically occupied for the admission');
}

console.log('Inpatient bed transfer workflow contract passed');
