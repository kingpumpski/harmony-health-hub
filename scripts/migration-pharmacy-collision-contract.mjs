import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const base = 'supabase/migrations/';
const pharmacyPath = path.join(root, base + '20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql');
const appointmentPath = path.join(root, base + '20261002130000_scope_appointment_workflows_to_active_facility.sql');
const legacyPath = path.join(root, base + '20261002132000_pharmacy_legacy_stock_reconciliation_rpc.sql');
const patientHubPath = path.join(root, base + '20261002132500_patient_hub_read_rpc_get_compatibility.sql');
const categoryPath = path.join(root, base + '20261002132500_pharmacy_global_category_edit.sql');
const forwardRepairPath = path.join(root, base + '20261127100300_fix_pharmacy_workspace_admin_facility_scope.sql');
const [pharmacy, appointment, legacy, patientHub, category, forwardRepair] =
  [pharmacyPath, appointmentPath, legacyPath, patientHubPath, categoryPath, forwardRepairPath].map(file => fs.readFileSync(file, 'utf8'));

function functionNames(sql) {
  return [...sql.matchAll(/CREATE(?: OR REPLACE)? FUNCTION public\.([a-z0-9_]+)/gi)].map(match => match[1].toLowerCase());
}
function functionStatement(sql, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = sql.match(new RegExp('CREATE(?: OR REPLACE)? FUNCTION public\\.' + escaped + '\\([\\s\\S]*?\\$function\\$[\\s\\S]*?\\$function\\$;', 'i'));
  if (!match) throw new Error('Missing function statement: ' + name);
  return match[0].replace(/\s+/g, ' ').trim();
}
const pharmacyFns = new Set(functionNames(pharmacy));
const appointmentFns = new Set(functionNames(appointment));
for (const name of pharmacyFns) if (appointmentFns.has(name)) {
  throw new Error('20261002130000 same-version pair unexpectedly overlaps function: ' + name);
}
if (!pharmacy.includes('CREATE TABLE IF NOT EXISTS public.medication_catalogue')) {
  throw new Error('Expected pharmacy catalogue table creation');
}
if (!appointment.includes('CREATE OR REPLACE FUNCTION public.get_appointment_worklist')) {
  throw new Error('Expected appointment worklist replacement');
}

const bypasses = [
  /AND \(v_admin OR \(v_facility IS NOT NULL AND p\.facility_id = v_facility\)\)/,
  /WHERE d\.status <> 'cancelled' AND \(v_admin OR \(v_facility IS NOT NULL AND d\.facility_id = v_facility\)\)/
];
for (const pattern of bypasses) {
  if (!pattern.test(pharmacy)) throw new Error('Reviewed admin facility-bypass evidence changed: ' + pattern);
}
const workspaceStart = pharmacy.indexOf('CREATE OR REPLACE FUNCTION public.get_pharmacy_workspace');
const workspaceEnd = pharmacy.indexOf('$function$;', workspaceStart);
if (workspaceStart < 0 || workspaceEnd < 0) throw new Error('Could not isolate get_pharmacy_workspace body');
const workspace = pharmacy.slice(workspaceStart, workspaceEnd);
if (!workspace.includes("v_admin := public.has_role(v_uid, 'admin')")) {
  throw new Error('Expected admin role classification in pharmacy workspace');
}

// The historical bypass is retained as provenance evidence above. The later
// forward-only correction must close it for all patient-linked clinical rows.
const repairedStart = forwardRepair.indexOf('CREATE OR REPLACE FUNCTION public.get_pharmacy_workspace');
const repairedEnd = forwardRepair.indexOf('$function$;', repairedStart);
if (repairedStart < 0 || repairedEnd < 0) throw new Error('Could not isolate the forward pharmacy workspace repair');
const repairedWorkspace = forwardRepair.slice(repairedStart, repairedEnd);
for (const token of [
  'AND v_facility IS NOT NULL AND p.facility_id = v_facility',
  'AND v_facility IS NOT NULL AND d.facility_id = v_facility',
  'AND p.facility_id = v_facility',
  'WHERE i.active AND i.facility_id = v_facility',
  'AND s.facility_id = v_facility'
]) {
  if (!repairedWorkspace.includes(token)) throw new Error('Forward pharmacy repair is missing facility predicate: ' + token);
}
if (repairedWorkspace.includes('(v_admin OR (v_facility IS NOT NULL AND p.facility_id = v_facility))') ||
    repairedWorkspace.includes('(v_admin OR (v_facility IS NOT NULL AND d.facility_id = v_facility))')) {
  throw new Error('Forward pharmacy repair must not preserve the historical administrator facility bypass');
}
if (!forwardRepair.includes('SET search_path = \'\'' ) ||
    !forwardRepair.includes('REVOKE ALL ON FUNCTION public.get_pharmacy_workspace(integer) FROM PUBLIC, anon;') ||
    !forwardRepair.includes('GRANT EXECUTE ON FUNCTION public.get_pharmacy_workspace(integer) TO authenticated;')) {
  throw new Error('Forward pharmacy repair must preserve hardened execution and authenticated-only RPC access');
}
for (const relation of ['public.patients p', 'public.prescriptions r', 'public.pharmacy_dispensing_plans d']) {
  if (!workspace.includes(relation)) throw new Error('Expected reviewed workspace relation: ' + relation);
}

const legacyStatements = [pharmacy, legacy, category].map(sql =>
  functionStatement(sql, 'assign_unattributed_pharmacy_inventory')
);
if (!legacyStatements.every(statement => statement === legacyStatements[0])) {
  throw new Error('assign_unattributed_pharmacy_inventory definitions are no longer whitespace-equivalent');
}
const patientHubTargets = [
  'get_patient_appointments(uuid, integer)',
  'get_patient_admission_history(uuid)',
  'get_patient_hub_clinical_snapshot(uuid)',
  'get_patient_current_treatment_snapshot(uuid, uuid)',
  'get_patient_bmi_context(uuid)',
  'get_attending_patient_history(uuid, uuid)'
];
for (const target of patientHubTargets) {
  if (!patientHub.includes('ALTER FUNCTION public.' + target + ' STABLE')) {
    throw new Error('Missing Patient Hub STABLE volatility adjustment: ' + target);
  }
}
if (!category.includes('CREATE FUNCTION public.update_pharmacy_inventory_item(')) {
  throw new Error('Expected pharmacy category-edit inventory update RPC');
}
console.log('[migration-pharmacy-collision] PASS: historical pharmacy bypass is pinned as provenance evidence and the forward repair scopes patient-linked clinical rows, inventory and POS data to the active facility. Unassigned legacy-stock visibility remains a separate reconciliation policy.');
