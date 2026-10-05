import fs from 'node:fs';

const inpatient = fs.readFileSync('src/pages/InpatientManagement.tsx', 'utf8');
const admissions = fs.readFileSync('src/pages/AdmissionManagement.tsx', 'utf8');
const sidebar = fs.readFileSync('src/components/layout/Sidebar.tsx', 'utf8');
const search = fs.readFileSync('src/lib/globalWorkspaceSearch.ts', 'utf8');

for (const [name, source, needles] of [
  ['InpatientManagement', inpatient, [
    "supabase.rpc('get_admission_workspace'",
    "supabase.rpc('get_operational_workspace'",
    'Array.isArray(admissionData)',
    "admissionData as { admissions?: Admission[] }",
  ]],
  ['AdmissionManagement', admissions, [
    "db.rpc('get_admission_workspace'",
    "db.rpc('get_operational_workspace'",
    'Array.isArray(workspace)',
    "workspace?.admissions ?? []",
    'searchPatientDirectory',
  ]],
  ['Sidebar', sidebar, [
    "item(Stethoscope, 'Healthcare', '/clinical-operations'",
    "p className="truncate text-xs font-medium">Healthcare</p>",
  ]],
  ['GlobalWorkspaceSearch', search, [
    "title:'Healthcare'",
    "href:'/clinical-operations'",
  ]],
]) {
  for (const needle of needles) {
    if (!source.includes(needle)) throw new Error(name + ' missing runtime contract: ' + needle);
  }
}

for (const forbidden of [
  "supabase.from('admissions')",
  "supabase.from('ward_beds')",
  "supabase.from('ward_units')",
]) {
  if (inpatient.includes(forbidden) || admissions.includes(forbidden)) {
    throw new Error('Inpatient UI must not bypass secured workspace RPCs: ' + forbidden);
  }
}

const migrations = fs.readdirSync('supabase/migrations')
  .filter((name) => name.endsWith('.sql'))
  .sort()
  .map((name) => fs.readFileSync('supabase/migrations/' + name, 'utf8'))
  .join('\n');

const admissionDef = migrations.slice(migrations.lastIndexOf('CREATE OR REPLACE FUNCTION public.get_admission_workspace'));
if (!admissionDef.includes("public.has_role(auth.uid(),'system_superuser'::public.app_role)")) {
  throw new Error('Admission workspace must resolve system_superuser through has_role');
}
if (!admissionDef.includes("public.has_role(auth.uid(),'it_admin'::public.app_role)")) {
  throw new Error('Admission workspace must resolve it_admin through has_role');
}
if (!admissionDef.includes("v_role <> 'system_superuser' AND v_facility IS NULL")) {
  throw new Error('Admission workspace must require active facility for non-system-superuser roles');
}
if (!admissionDef.includes("COALESCE(a.facility_id,b.facility_id,w.facility_id,p.facility_id)=v_facility")) {
  throw new Error('Admission workspace must enforce facility attribution');
}

const wardDef = migrations.slice(migrations.lastIndexOf("ELSIF _module='ward'"));
if (!wardDef.includes("v_role NOT IN ('admin','it_admin','system_superuser','practitioner','nurse','midwife','specialist_nurse')")) {
  throw new Error('Ward workspace role parity is incomplete');
}

console.log('Inpatient runtime workspace and Healthcare navigation contracts passed.');
