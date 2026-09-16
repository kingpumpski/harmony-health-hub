import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260916190000_nextgen_admission_bed_concurrency.sql','utf8');
const packageJson = JSON.parse(fs.readFileSync('package.json','utf8'));
const workflow = fs.readFileSync('.github/workflows/quality.yml','utf8');

const required = [
  ['server-authoritative admission creation', /CREATE OR REPLACE FUNCTION public\.create_admission_workflow/],
  ['server-authoritative discharge', /CREATE OR REPLACE FUNCTION public\.discharge_admission_workflow/],
  ['active admission duplicate protection', /already has an active admission/],
  ['bed row locking during admission', /ward_beds[\s\S]*?FOR UPDATE/],
  ['available bed gate', /status='available'/],
  ['atomic admission-to-bed linkage', /admission_id=v_id/],
  ['bed row locking during assignment', /SELECT \* INTO b FROM public\.ward_beds WHERE id=_bed_id FOR UPDATE/],
  ['assignment admission ownership check', /a\.patient_id <> _patient_id/],
  ['duplicate bed protection for admission', /Admission already has a bed/],
  ['active admission protection on bed release', /Active admission must be discharged before releasing its bed/],
  ['active nursing care-plan discharge gate', /Active nursing care plans must be completed or cancelled before discharge/],
  ['admission-linked care-plan check', /nursing_care_plans[\s\S]*?admission_id=_admission_id[\s\S]*?status='active'/],
  ['discharge releases linked bed', /status='cleaning'/],
  ['direct admissions DML lockdown', /REVOKE INSERT,UPDATE,DELETE ON TABLE public\.admissions FROM authenticated/],
  ['direct ward bed DML lockdown', /REVOKE INSERT,UPDATE,DELETE ON TABLE public\.ward_beds FROM authenticated/],
  ['public admission RPC isolation', /REVOKE ALL ON FUNCTION public\.create_admission_workflow\(UUID,TEXT,TEXT,TEXT\) FROM PUBLIC,anon/],
  ['authenticated admission execution', /GRANT EXECUTE ON FUNCTION public\.create_admission_workflow\(UUID,TEXT,TEXT,TEXT\) TO authenticated/],
  ['package wiring', /test:nextgen-admission-bed-concurrency/],
  ['quality workflow wiring', /npm run test:nextgen-admission-bed-concurrency/],
];

for (const [label, pattern] of required) {
  const source = label === 'package wiring' ? JSON.stringify(packageJson.scripts) : label === 'quality workflow wiring' ? workflow : migration;
  if (!pattern.test(source)) throw new Error(`Admission/bed contract missing: ${label}`);
}

if (packageJson.scripts['test:nextgen-admission-bed-concurrency'] !== 'node scripts/test-nextgen-admission-bed-concurrency.mjs') {
  throw new Error('Admission/bed package script has incorrect command');
}

console.log('Next-generation admission/bed concurrency contract checks passed.');
