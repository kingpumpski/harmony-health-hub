import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20260929184500_harden_security_definer_auth_helper_paths_batch5.sql';
const m = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
const signatures = [
  'can_edit_patient_record(uuid)',
  'claim_notification_queue(integer)',
  'current_user_can_edit_patient_record()',
  'current_user_facility_id()',
  'current_user_has_catalogue_create_permission(text)',
  'current_user_has_facility_access(uuid)',
  'current_user_has_role(app_role)',
  'current_user_is_clinical_staff()',
];

for (const signature of signatures) {
  if (!m.includes('public.' + signature)) throw new Error('Missing ' + signature);
}
if ((m.match(/set search_path = pg_catalog, public/g) || []).length !== signatures.length) {
  throw new Error('Search-path hardening count mismatch');
}

const guardStart = m.indexOf('do $batch5_facility_helper$');
const guardEnd = m.indexOf('$batch5_facility_helper$;', guardStart);
if (guardStart < 0 || guardEnd < 0) throw new Error('Batch 5 facility helper replay guard is missing.');
const facilityGuard = m.slice(guardStart, guardEnd + '$batch5_facility_helper$;'.length);
for (const required of [
  "to_regprocedure('public.current_user_facility_id()')",
  'p.proconfig',
  'search_path=""',
  "alter function public.current_user_facility_id() set search_path = pg_catalog, public",
]) {
  if (!facilityGuard.includes(required)) throw new Error('Batch 5 facility helper replay guard missing: ' + required);
}
if (!facilityGuard.includes('if v_function is not null')) {
  throw new Error('Batch 5 must defer facility helper hardening when the canonical function is absent.');
}
if (!facilityGuard.includes('not coalesce(v_config @> array')) {
  throw new Error('Batch 5 must preserve an already-empty facility helper search_path.');
}

console.log('Batch 5 SECURITY DEFINER authorization helper contract passed.');
