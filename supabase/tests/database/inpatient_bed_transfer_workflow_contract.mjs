import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260924143000_add_atomic_inpatient_bed_transfer_workflow.sql',
  'utf8',
);

const required = [
  "CREATE OR REPLACE FUNCTION public.transfer_inpatient_bed(",
  "PERFORM pg_advisory_xact_lock(hashtextextended(_admission_id::text, 0))",
  "FROM public.admissions",
  "FOR UPDATE",
  "v_admission.status <> 'admitted'",
  "FROM public.ward_beds",
  "v_target.status <> 'available'",
  "v_target.patient_id IS NOT NULL",
  "v_target.admission_id IS NOT NULL",
  "status = 'occupied'",
  "status = 'cleaning'",
  "UPDATE public.ward_beds",
  "INSERT INTO public.care_transitions",
  "transition_type,",
  "'transfer'",
  "completed_at",
  "public.record_system_audit",
  "REVOKE ALL ON FUNCTION public.transfer_inpatient_bed(uuid, uuid, text) FROM PUBLIC, anon",
  "GRANT EXECUTE ON FUNCTION public.transfer_inpatient_bed(uuid, uuid, text) TO authenticated",
];

for (const fragment of required) {
  if (!migration.includes(fragment)) {
    throw new Error(`Missing inpatient bed transfer contract fragment: ${fragment}`);
  }
}

if (!/UPDATE public\.ward_beds[\s\S]*status = 'cleaning'[\s\S]*patient_id = NULL[\s\S]*admission_id = NULL/.test(migration)) {
  throw new Error('Source bed is not released atomically to cleaning');
}

if (!/UPDATE public\.ward_beds[\s\S]*patient_id = v_admission\.patient_id[\s\S]*admission_id = v_admission\.id[\s\S]*status = 'occupied'/.test(migration)) {
  throw new Error('Target bed is not atomically occupied for the admission');
}

console.log('Inpatient bed transfer workflow contract passed');
