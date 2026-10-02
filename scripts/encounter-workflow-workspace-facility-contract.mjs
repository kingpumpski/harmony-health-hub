#!/usr/bin/env node
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20261002193000_harden_encounter_workflow_workspace_facility_boundary.sql',
  'utf8'
).replace(/\s+/g, ' ').trim().toLowerCase();

const ui = fs.readFileSync('src/components/EncounterWorkflowOverlay.tsx', 'utf8');

for (const needle of [
  'create or replace function public.get_encounter_workflow_workspace()',
  'stable security definer',
  'set search_path = \'\'',
  'auth.uid() is not null',
  'public.hms_test_mode_enabled()',
  'public.hms_test_facility_id()',
  'e.facility_id = public.hms_test_facility_id()',
  'p.facility_id = public.hms_test_facility_id()',
  'not public.hms_test_mode_enabled()',
  'public.current_user_facility_id()',
  'revoke all on function public.get_encounter_workflow_workspace() from public, anon',
  'grant execute on function public.get_encounter_workflow_workspace() to authenticated',
  "and e.status in ('draft', 'completed')"
]) {
  if (!migration.includes(needle)) throw new Error(`Missing encounter workspace boundary: ${needle}`);
}

if (!ui.includes("rpc('get_encounter_workflow_workspace')")) {
  throw new Error('Encounter workflow overlay must use the protected workspace RPC');
}

const testModeIndex = migration.indexOf('public.hms_test_mode_enabled()');
const adminIndex = migration.indexOf("public.current_user_has_role('admin'::public.app_role)");
if (testModeIndex < 0 || adminIndex < 0 || testModeIndex > adminIndex) {
  throw new Error('Encounter workspace must evaluate test-mode isolation before privileged-role exceptions');
}

console.log('Encounter workflow workspace facility boundary contract passed.');
