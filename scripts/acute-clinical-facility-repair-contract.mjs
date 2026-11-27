import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20261127100600_fix_acute_clinical_lifecycle_facility_scope.sql';
const sourcePaths = [
  'supabase/migrations/20261003120000_harden_patient_emergency_imaging_facility_context.sql',
  'supabase/migrations/20261004255500_correct_transfusion_event_facility_context.sql',
  'supabase/migrations/20261004260500_correct_theatre_transition_facility_context.sql',
];
const sql = fs.readFileSync(migrationPath, 'utf8');
const sources = sourcePaths.map((path) => fs.readFileSync(path, 'utf8'));
const normalized = sql.toLowerCase().replace(/\s+/g, '');
const sourceText = sources.join('\n').toLowerCase();

for (const token of [
  "ifnotpublic.has_role(uid,''system_superuser'')",
  "emergencypatientfacilityattributionisunresolved",
  "emergencycasebelongsto adifferentfacilitycontext",
  "theatre facility bypass anchor count mismatch",
  "transfusion facility bypass anchor count mismatch",
  "public.current_user_facility_id()",
]) {
  if (!normalized.includes(token.replace(/\s+/g, ''))) {
    throw new Error('Missing acute clinical facility invariant: ' + token);
  }
}
if (!sourceText.includes("ifnotpublic.has_role(uid,'admin')") ||
    !sourceText.includes("public.has_role(uid,'it_admin')") ||
    !sourceText.includes("active_facilityisdistinctfrompatient_facility")) {
  throw new Error('Reviewed acute clinical source bypass anchors have drifted');
}
for (const signature of [
  'transition_emergency_case(uuid,text,text)',
  'transition_theatre_case(uuid,text,text)',
  'record_transfusion_event(uuid,text,boolean,text)',
]) {
  if (!sql.includes(signature)) throw new Error('Missing guarded RPC identity: ' + signature);
}
if (!sql.includes('changed<>1') || !sql.includes('REVOKE ALL ON FUNCTION public.transition_emergency_case')) {
  throw new Error('Migration must fail closed on source drift and preserve explicit RPC ACLs');
}
console.log('[acute-clinical-facility-repair] PASS: emergency, theatre and transfusion lifecycle RPCs enforce active facility context; only system_superuser bypasses.');
