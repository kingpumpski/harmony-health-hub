import fs from 'node:fs';

const contextMigration = fs.readFileSync('supabase/migrations/20261002070000_allow_superadmin_facility_context_override.sql', 'utf8');
const historyMigration = fs.readFileSync('supabase/migrations/20261002071000_superadmin_patient_history_context_access.sql', 'utf8');
const settings = fs.readFileSync('src/pages/admin/Settings.tsx', 'utf8');
const patientHub = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
const notificationFunction = fs.readFileSync('supabase/functions/notification-provider-config/index.ts', 'utf8');
const onboardingMigration = fs.readFileSync('supabase/migrations/20261004271000_complete_platform_facility_onboarding_bootstrap.sql', 'utf8');
const lifecycleMigration = fs.readFileSync('supabase/migrations/20261004272000_add_platform_facility_lifecycle_workflows.sql', 'utf8');
const userFacilityMigration = fs.readFileSync('supabase/migrations/20261004273000_complete_platform_user_facility_membership_workflows.sql', 'utf8');
const adminUsers = fs.readFileSync('src/pages/admin/AdminUsers.tsx', 'utf8');
const adminUserFunction = fs.readFileSync('supabase/functions/admin-create-user/index.ts', 'utf8');
const adminUserProvisioning = fs.readFileSync('supabase/functions/_shared/admin-user-provisioning.ts', 'utf8');

for (const needle of [
  'public.has_role(auth.uid(), \'system_superuser\'::public.app_role)',
  'public.list_facilities_for_superadmin_context()',
  'public.current_user_facility_id()',
  'REVOKE ALL ON FUNCTION public.set_active_facility_context(uuid) FROM PUBLIC, anon',
]) {
  if (!contextMigration.includes(needle)) throw new Error('Facility context migration missing guard: ' + needle);
}
for (const needle of [
  'public.assert_patient_facility_read_context(uuid)',
  'public.get_patient_profile_for_user(uuid)',
  'public.get_patient_appointments(uuid,integer)',
  'public.get_patient_hub_clinical_snapshot(uuid)',
  'public.get_patient_admission_history(uuid)',
  'public.start_appointment_encounter(uuid,text,text)',
  'system_superuser',
]) {
  if (!historyMigration.includes(needle)) throw new Error('Patient history migration missing scoped superadmin access: ' + needle);
}
for (const needle of [
  'Active Facility Context',
  'list_facilities_for_superadmin_context',
  'set_active_facility_context',
  'window.location.reload()',
]) {
  if (!settings.includes(needle)) throw new Error('Superadmin facility selector missing: ' + needle);
}
if (!patientHub.includes("db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 }, { get: true })")) {
  throw new Error('Patient appointment history must use GET RPC invocation for the STABLE read function');
}
for (const needle of [
  'Access-Control-Allow-Origin',
  'Access-Control-Allow-Headers',
  "req.method==='OPTIONS'",
  "'system_superuser'",
]) {
  if (!notificationFunction.includes(needle)) throw new Error('Notification provider function missing CORS/superadmin support: ' + needle);
}
for (const needle of [
  "public.initialize_facility_notification_onboarding(v_facility.id)",
  "Only system super administrators may onboard facilities",
  "REVOKE ALL ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) FROM PUBLIC, anon",
  "GRANT EXECUTE ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) TO authenticated",
]) {
  if (!onboardingMigration.includes(needle)) throw new Error('Platform facility onboarding bootstrap missing guard: ' + needle);
}
for (const needle of [
  "platform_update_facility(_facility_id uuid",
  "platform_set_facility_active(_facility_id uuid",
  "Only system super administrators may update facilities",
  "Facility cannot be deactivated while users still have it as their active facility context",
  "REVOKE ALL ON FUNCTION public.platform_update_facility(uuid,text,text,text,text,text,text) FROM PUBLIC,anon",
  "REVOKE ALL ON FUNCTION public.platform_set_facility_active(uuid,boolean) FROM PUBLIC,anon",
]) {
  if (!lifecycleMigration.includes(needle)) throw new Error('Platform facility lifecycle migration missing guard: ' + needle);
}
for (const needle of [
  "platform_list_user_facility_memberships(_user_id uuid)",
  "platform_set_user_facility_membership(_user_id uuid",
  "platform_set_user_active_facility(_user_id uuid",
  "public.has_role(v_actor,'system_superuser'::public.app_role)",
  "REVOKE ALL ON FUNCTION public.platform_set_user_facility_membership(uuid,uuid,boolean,text) FROM PUBLIC,anon,authenticated",
  "GRANT EXECUTE ON FUNCTION public.platform_set_user_active_facility(uuid,uuid) TO authenticated",
]) {
  if (!userFacilityMigration.includes(needle)) throw new Error('Platform user facility workflow missing guard: ' + needle);
}
for (const needle of [
  "user?.role === 'it_admin'",
  "action: 'set_facility_membership'",
  "action: 'set_active_facility'",
  "facilityId",
  "platform_set_user_facility_membership",
  "platform_set_user_active_facility",
]) {
  if (!adminUsers.includes(needle) && !adminUserFunction.includes(needle)) throw new Error('Admin user facility onboarding missing: ' + needle);
}
if (!adminUserFunction.includes("['admin','it_admin','system_superuser']") || !adminUserProvisioning.includes("['admin','it_admin','system_superuser']")) {
  throw new Error('IT Admin must retain user-management authorization');
}
console.log('Superadmin facility context, patient history, notification CORS, onboarding bootstrap, facility lifecycle, and platform user-facility administration contract passed');
