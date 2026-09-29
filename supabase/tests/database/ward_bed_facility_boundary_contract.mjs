import fs from 'node:fs';
import path from 'node:path';

const migration = fs.readFileSync(
  path.join(process.cwd(), 'supabase/migrations/20260929070000_ward_bed_facility_boundary.sql'),
  'utf8',
);

const required = [
  "CREATE OR REPLACE FUNCTION public.set_ward_bed_status(",
  "public.has_facility_access(uid, v_bed.facility_id)",
  "RAISE EXCEPTION 'Facility access required'",
  "v_bed.status = 'occupied'",
  "patient_id IS NOT NULL",
  "admission_id IS NOT NULL",
];

const missing = required.filter((fragment) => !migration.includes(fragment));
if (missing.length) {
  console.error('Ward-bed facility boundary contract failed:');
  for (const fragment of missing) console.error(`- ${fragment}`);
  process.exitCode = 1;
} else {
  console.log('Ward-bed facility boundary contract: 6/6 invariants present');
}
