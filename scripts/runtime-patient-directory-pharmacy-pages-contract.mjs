import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20261005123000_unify_runtime_patient_directory_and_pharmacy_zero_price_edits.sql',
  'utf8',
).toLowerCase();
const triage = fs.readFileSync('src/pages/Triage.tsx','utf8');
const anaesthesia = fs.readFileSync('src/pages/AnestheticAssessment.tsx','utf8');
const billing = fs.readFileSync('src/pages/Billing.tsx','utf8');
const transitions = fs.readFileSync('src/pages/CareTransitions.tsx','utf8');
const globalSearch = fs.readFileSync('src/lib/globalWorkspaceSearch.ts','utf8');
const pages = fs.readFileSync('.github/workflows/pages.yml','utf8');
const aiClinicalAssist = fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts','utf8');
const formNormalizer = fs.readFileSync('src/components/system/FormFieldIdentityNormalizer.tsx','utf8');

for (const needle of [
  'create function public.get_patient_directory(',
  'p.facility_id = active_facility',
  'public.current_user_facility_id()',
  'revoke all on function public.get_patient_directory(text,integer) from public, anon',
  'grant execute on function public.get_patient_directory(text,integer) to authenticated',
  'stock_quantity=coalesce(_stock_quantity,0)',
  'unit_price=coalesce(_unit_price,0)',
  'if coalesce(_stock_quantity,0) > 0 and _expiry_date is null',
  'set drug_name=pg_catalog.btrim(_drug_name)',
  'create or replace function public.create_pharmacy_inventory_item(',
  'if coalesce(_stock_quantity,0) > 0 and _expiry_date is null',
]) {
  if (!migration.includes(needle)) throw new Error('Missing runtime migration contract: ' + needle);
}

for (const [name, source] of [
  ['Triage', triage],
  ['AnestheticAssessment', anaesthesia],
  ['Billing', billing],
  ['CareTransitions', transitions],
  ['GlobalSearch', globalSearch],
]) {
  if (!source.includes("get_patient_directory")) throw new Error(name + ' must use canonical patient directory');
  if (source.includes("supabase.from('patients')")) throw new Error(name + ' must not directly query patients');
}

if (!aiClinicalAssist.includes("supabase.rpc('get_patient_directory', { _limit: 500 })")) {
  throw new Error('AI nurse dashboard must use canonical patient directory');
}

for (const needle of [
  'associateLabels()',
  'label.htmlFor = nested.id',
  'label.htmlFor = field.id',
  'field.setAttribute(\"autocomplete\", value)',
  'field.setAttribute(\"aria-label\", readableFieldName(field))',
]) {
  if (!formNormalizer.includes(needle)) throw new Error('Missing form accessibility hardening contract: ' + needle);
}

if (pages.includes('cp dist/index.html dist/404.html')) {
  throw new Error('GitHub Pages workflow must preserve the generated redirecting 404.html');
}

console.log('Runtime patient directory, pharmacy edit and GitHub Pages fallback contracts passed.');
