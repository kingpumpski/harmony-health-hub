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
if (!globalSearch.includes("const DIRECTORY_ROLES = [...CLINICAL_ROLES, ...ACCOUNTING_ROLES, 'front_desk', 'canteen'];")) {
  throw new Error('Global patient search role policy must include front desk and canteen directory roles');
}

const pages = fs.readFileSync('.github/workflows/pages.yml','utf8');
const aiClinicalAssist = fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts','utf8');
const patientDirectory = fs.readFileSync('src/lib/patientDirectory.ts','utf8');
const formNormalizer = fs.readFileSync('src/components/system/FormFieldIdentityNormalizer.tsx','utf8');
const pharmacy = fs.readFileSync('src/pages/Pharmacy.tsx','utf8');
const canteenMeals = read('src/pages/CanteenMeals.tsx');
const header = read('src/components/layout/Header.tsx');
const patientHub = fs.readFileSync('src/pages/patients/PatientHub.tsx','utf8');
const platformWorkspace = fs.readFileSync('supabase/migrations/20261006113000_reconcile_platform_admin_workspace_context.sql','utf8').toLowerCase();

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

for (const needle of [
  "is_platform_admin boolean;",
  "is_platform_admin := public.has_role(uid,'admin'::public.app_role)",
  "if not is_platform_admin and active_facility is null",
  "(is_platform_admin and active_facility is null or p.facility_id = active_facility)",
]) {
  if (!platformWorkspace.includes(needle)) throw new Error('Platform-admin patient directory context contract missing: ' + needle);
}

const careTransitions = transitions;
if (careTransitions.includes("supabase.rpc('get_admission_workspace', { _limit: 500 }, { get: true })") || careTransitions.includes("supabase.rpc('get_operational_workspace', { _module: 'ward', _limit: 500 }, { get: true })")) {
  throw new Error('CareTransitions must keep VOLATILE workspace RPCs on POST transport');
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

for (const needle of [
  "db.rpc('update_pharmacy_inventory_item', { _item_id: editingInventoryId, ...payload })",
  '_unit_price: inventoryForm.unit_price',
  '_stock_quantity: inventoryForm.stock_quantity',
  '_reorder_level: inventoryForm.reorder_level',
  'Number(item.unit_price ?? 0)',
]) {
  if (!pharmacy.includes(needle)) throw new Error('Pharmacy edit payload must preserve numeric zero values: ' + needle);
}

if (!canteenMeals.includes("get_patient_portal_meal_menus', { _service_date: date })")) throw new Error('Patient meal menu read must use standard POST transport');
if (!header.includes('void db.rpc("mark_notification_read", { _notification_id: n.id }).then(() => loadNotifications()).catch(() => loadNotifications())')) throw new Error('Notification read refresh must await RPC promise');
if (!patientHub.includes(".rpc('create_patient_appointment'")) {
  throw new Error('Patient Hub appointment creation must use the canonical appointment RPC');
}

if (!patientDirectory.includes("supabase.rpc('get_patient_directory' as never")) {
  throw new Error('Patient directory helper must use the canonical get_patient_directory RPC');
}
if (patientDirectory.includes("supabase.rpc('search_patient_directory'")) {
  throw new Error('Patient directory helper must not fall back to the legacy search_patient_directory RPC');
}

if (!aiClinicalAssist.includes("supabase.rpc('get_patient_directory', { _limit: 500 })")) {
  throw new Error('AI nurse dashboard must use canonical patient directory');
}

for (const needle of [
  'associateLabels()',
  'label.htmlFor = nested.id',
  'label.htmlFor = field.id',
  'field.setAttribute("autocomplete", value)',
  'field.setAttribute("aria-label", readableFieldName(field))',
]) {
  if (!formNormalizer.includes(needle)) throw new Error('Missing form accessibility hardening contract: ' + needle);
}

if (pages.includes('cp dist/index.html dist/404.html')) {
  throw new Error('GitHub Pages workflow must preserve the generated redirecting 404.html');
}

console.log('Runtime patient directory, pharmacy edit and GitHub Pages fallback contracts passed.');
