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
    'Healthcare',
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

if (!fs.existsSync('supabase/migrations/20261006113000_reconcile_platform_admin_workspace_context.sql')) {
  throw new Error('Platform-admin workspace context reconciliation migration is missing');
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
if (!admissionDef.includes("v_platform_admin := v_role IN ('admin','it_admin','system_superuser')")) {
  throw new Error('Admission workspace must resolve platform administrator roles');
}
if (!admissionDef.includes("IF NOT v_platform_admin AND v_facility IS NULL")) {
  throw new Error('Admission workspace must require active facility for non-platform roles');
}
if (!admissionDef.includes("v_platform_admin AND v_facility IS NULL")) {
  throw new Error('Admission workspace must support platform administrators without a selected facility');
}
if (!admissionDef.includes("COALESCE(a.facility_id,b.facility_id,w.facility_id,p.facility_id)=v_facility")) {
  throw new Error('Admission workspace must enforce facility attribution');
}

const wardDef = migrations.slice(migrations.lastIndexOf("ELSIF _module='ward'"));
if (!wardDef.includes('IF NOT v_platform_admin AND v_role NOT IN')) {
  throw new Error('Ward workspace must preserve platform-admin role bypass');
}
if (!wardDef.includes("v_platform_admin AND v_facility IS NULL")) {
  throw new Error('Ward workspace must support platform administrators without a selected facility');
}

for (const [name, source] of [['Sidebar', sidebar], ['GlobalWorkspaceSearch', search]]) {
  if (source.includes('Clinical Operation')) {
    throw new Error(name + ' must not expose the retired Clinical Operation label');
  }
}

console.log('Inpatient runtime workspace and Healthcare navigation contracts passed.');
