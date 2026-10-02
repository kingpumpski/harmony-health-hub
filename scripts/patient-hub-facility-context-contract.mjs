import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261002115106_scope_patient_hub_to_active_facility.sql', 'utf8');
const page = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
const healthApi = fs.readFileSync('src/lib/healthApi.ts', 'utf8');

for (const needle of [
  "An active facility is required to search patient records",
  "An active facility is required to access patient records",
  "p.facility_id = active_facility",
  "public.current_user_has_facility_access(p.facility_id)",
  "revoke all on function public.search_patient_directory(text, integer) from public, anon",
  "revoke all on function public.get_patient_profile_for_user(uuid) from public, anon",
  "grant execute on function public.search_patient_directory(text, integer) to authenticated",
  "grant execute on function public.get_patient_profile_for_user(uuid) to authenticated",
  "public.hms_current_user_is_test_user()",
  "public.hms_test_facility_id()",
  "active_facility := test_facility",
  "is_admin := false",
  "public.assert_patient_facility_read_context(_patient_id)",
  "create or replace function public.get_patient_directory_record(_patient_id uuid)",
  "revoke all on function public.get_patient_directory_record(uuid) from public, anon",
  "public.has_role(uid, 'system_superuser'::public.app_role)",
  "coalesce(p.status, 'active') <> 'inactive'"
]) {
  if (!migration.includes(needle)) throw new Error("Patient facility-scope migration missing guard: " + needle);
}

if (!page.includes('Your account has no active facility context. Patient records are facility-scoped.')) {
  throw new Error('Patient Hub must explain missing active-facility context rather than showing a misleading not-found state');
}
if (!page.includes('This patient record was not found in your active facility, or your account does not have permission to view it.')) {
  throw new Error('Patient Hub must use a facility-aware not-found message');
}

for (const needle of [
  'UUID_PATTERN',
  'searchPatientDirectory(requestedId, 10)',
  'candidate.patient_code',
  'return fetchPatientProfile(exactMatch.id)'
]) {
  if (!healthApi.includes(needle)) throw new Error('Patient Hub canonical-ID fallback missing: ' + needle);
}

if (migration.includes('p.user_id = uid')) {
  throw new Error('Patient profile reads must not bypass facility/test-mode isolation through user ownership.');
}
if (!migration.includes('Test mode takes precedence over administrator privileges.')) {
  throw new Error('Test-user facility isolation must take precedence over administrator cross-facility access.');
}

console.log('Patient Hub active-facility access and legacy-link resolution contract passed');
