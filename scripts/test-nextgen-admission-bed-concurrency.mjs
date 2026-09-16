import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260916190000_nextgen_admission_bed_concurrency.sql','utf8');
const page = fs.readFileSync('src/pages/WardBedBoard.tsx','utf8');
const packageJson = JSON.parse(fs.readFileSync('package.json','utf8'));
const workflow = fs.readFileSync('.github/workflows/quality.yml','utf8');

const required = [
  ['server-authoritative admission creation', /CREATE OR REPLACE FUNCTION public\.create_admission_workflow/],
  ['server-authoritative discharge', /CREATE OR REPLACE FUNCTION public\.discharge_admission_workflow/],
  ['active admission duplicate protection', /already has an active admission/],
  ['patient admission concurrency lock', /pg_advisory_xact_lock\(hashtextextended\('hims:admission:' \|\| _patient_id::text, 0\)\)/],
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
];

for (const [label, pattern] of required) {
  if (!pattern.test(migration)) throw new Error(`Admission/bed contract missing: ${label}`);
}

const pageRequired = [
  ['ward board loads active admissions', /from\('admissions'\)\.select\('id,patient_id,status,discharged_at'\)\.eq\('status','admitted'\)\.is\('discharged_at',null\)/],
  ['ward board builds patient admission map', /admissionMap\[admission\.patient_id\]=admission\.id/],
  ['ward board sends admission to assignment RPC', /_admission_id:admissionId/],
  ['ward board blocks assignment without active admission', /Active admission required/],
  ['ward board only offers admitted patients', /patients\.filter\(p=>Boolean\(activeAdmissions\[p\.id\]\)\)/],
];
for (const [label, pattern] of pageRequired) {
  if (!pattern.test(page)) throw new Error(`Admission/bed UI continuity contract missing: ${label}`);
}

const packageSource = JSON.stringify(packageJson.scripts);
if (packageJson.scripts['test:nextgen-admission-bed-concurrency'] !== 'node scripts/test-nextgen-admission-bed-concurrency.mjs') {
  throw new Error('Admission/bed package script has incorrect command');
}
if (!/test:nextgen-admission-bed-concurrency/.test(packageSource)) throw new Error('Admission/bed package wiring missing');
if (!/npm run test:nextgen-admission-bed-concurrency/.test(workflow)) throw new Error('Admission/bed quality workflow wiring missing');

console.log('Next-generation admission/bed concurrency and inpatient UI continuity contract checks passed.');
