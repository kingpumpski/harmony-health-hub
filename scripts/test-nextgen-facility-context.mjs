import fs from 'node:fs';

const helper = fs.readFileSync('src/lib/nextGenFacilityContext.ts', 'utf8');
const controlCenter = fs.readFileSync('src/pages/admin/NextGenPlatformControlCenter.tsx', 'utf8');
const workspace = fs.readFileSync('src/pages/EnterpriseModuleWorkspace.tsx', 'utf8');
const authorization = fs.readFileSync('supabase/migrations/20261008153000_fix_platform_superuser_enterprise_access.sql', 'utf8');
const onboarding = fs.readFileSync('supabase/migrations/20261008160000_platform_facility_onboarding.sql', 'utf8');
const control = fs.readFileSync('src/pages/admin/NextGenPlatformControlCenter.tsx', 'utf8');

for (const needle of [
  "NEXT_GEN_FACILITY_CONTEXT_KEY = 'harmony:nextgen:facility-context'",
  'getNextGenFacilityContext',
  'setNextGenFacilityContext',
]) if (!helper.includes(needle)) throw new Error('Missing shared facility-context helper: ' + needle);

for (const needle of [
  'getNextGenFacilityContext',
  'setNextGenFacilityContext',
  'platform_list_facilities',
  'Platform facility context',
]) if (!controlCenter.includes(needle)) throw new Error('Platform Control Center is not using the shared facility context: ' + needle);

for (const needle of [
  'getNextGenFacilityContext',
  'setNextGenFacilityContext',
  'platform_list_facilities',
  'user_active_facilities',
  'Facility workspace context',
]) if (!workspace.includes(needle)) throw new Error('Enterprise workspace facility-context reconciliation missing: ' + needle);

for (const needle of [
  "public.has_role(_user_id,'system_superuser'::public.app_role)",
  'OR public.has_facility_access(_user_id,_facility_id)',
  'System Super Users may troubleshoot platform-wide without facility membership',
  'REVOKE ALL ON FUNCTION public.hms_user_can(uuid,text,text,uuid) FROM PUBLIC,anon',
]) if (!authorization.includes(needle)) throw new Error('System Super User authorization correction missing: ' + needle);

for (const needle of [
  "NOT public.has_role(auth.uid(), 'system_superuser'::public.app_role)",
  "Only system super administrators may onboard facilities",
  "INSERT INTO public.hms_facility_modules",
  "false, false, 'not_available'",
  "REVOKE ALL ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) FROM PUBLIC,anon",
  "RETURNS public.healthcare_facilities",
  "Facility code already exists",
]) if (!onboarding.includes(needle)) throw new Error('Governed facility onboarding contract missing: ' + needle);

for (const needle of [
  'Facility onboarding',
  'platform_create_facility',
  'canOnboardFacility',
  'New facilities start with modules disabled',
]) if (!control.includes(needle)) throw new Error('Facility onboarding UI contract missing: ' + needle);

console.log('Next-gen facility context, authorization, and onboarding contract: PASS');
