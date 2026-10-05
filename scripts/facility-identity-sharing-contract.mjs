import fs from 'node:fs';

const read = (p) => fs.readFileSync(p, 'utf8');
const governance = read('supabase/migrations/20260930104819_facility_identity_and_cross_facility_governance.sql');
const boundary = read('supabase/migrations/20260930105125_enforce_facility_owned_record_read_boundaries.sql');
const header = read('src/components/layout/Header.tsx');
const adminProvisioning = read('supabase/functions/_shared/admin-user-provisioning.ts');

const assert = (name, ok, message) => { if (!ok) throw new Error(message); console.log('✓', name); };

assert('system superuser role is modeled', governance.includes("system_superuser"), 'System Superuser role contract missing');
assert('cross-facility agreements are bilateral', governance.includes('facility_a_approved_by') && governance.includes('facility_b_approved_by'), 'Bilateral approval contract missing');
assert('cross-facility access is time bounded', governance.includes('effective_from') && governance.includes('effective_to'), 'Agreement effective window missing');
assert('facility governance RPCs are not anonymous', read('supabase/migrations/20260930111220_harden_facility_governance_rpc_privileges.sql').includes('revoke all on function public.approve_facility_data_sharing_agreement(uuid) from public,anon'), 'Governance RPCs must not be anonymously executable');
assert('cross-facility access is scoped', governance.includes('facility_data_sharing_agreement_scopes') && governance.includes('scope_code'), 'Agreement scope contract missing');
assert('authenticated users can read their active facility context', read('supabase/migrations/20261005170000_restore_authenticated_active_facility_select.sql').includes('grant select on table public.user_active_facilities to authenticated'), 'Authenticated active facility context reads must be granted');
assert('normal users cannot directly mutate facility context', governance.includes('revoke insert,update,delete on table public.user_active_facilities from authenticated') && read('supabase/migrations/20261005170000_restore_authenticated_active_facility_select.sql').includes('revoke insert, update, delete on table public.user_active_facilities from authenticated'), 'Direct facility context mutation must be denied');
assert('facility context switch RPC is disabled for application users', read('supabase/migrations/20260930105412_lock_facility_context_switching.sql').includes('revoke all on function public.set_active_facility_context(uuid) from public,anon,authenticated'), 'Application facility switching RPC must be disabled');
assert('new users receive facility membership', adminProvisioning.includes('facility_memberships') && adminProvisioning.includes('facility_id'), 'Provisioning must create facility membership');
assert('header has no facility switcher', !header.includes('set_active_facility_context') && !header.includes('get_user_facilities'), 'Header must not expose a facility switcher');
assert('facility-owned reads have restrictive guards', boundary.includes('as restrictive for select') && boundary.includes('current_user_can_select_facility_record'), 'Facility-owned read boundaries missing');
assert('global diagnosis catalogue remains facility-independent', !boundary.includes('diagnosis_standards') && !boundary.includes('icd_codes'), 'Global diagnosis catalogue must not inherit facility isolation');
assert('facility diagnosis standard mapping is not facility-isolated', read('supabase/migrations/20260930112000_global_diagnosis_catalogue_access.sql').includes('drop policy if exists facility_identity_select_guard on public.facility_diagnosis_standards'), 'Facility standard mapping must not restrict access to the shared diagnosis catalogue');
console.log('Facility identity and cross-facility governance contract passed.');
