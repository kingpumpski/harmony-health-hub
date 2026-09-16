import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const migration = read('supabase/migrations/20260916140000_nextgen_device_lifecycle_workflow.sql');

for (const token of [
  'CREATE OR REPLACE FUNCTION public.register_platform_device',
  'CREATE OR REPLACE FUNCTION public.transition_platform_device',
  'CREATE OR REPLACE FUNCTION public.record_platform_device_heartbeat',
  "lifecycle_state = 'onboarding'",
  "current_state = 'proposed' AND normalized_target IN ('onboarding','retired')",
  "current_state = 'active' AND normalized_target IN ('degraded','quarantined','maintenance','retired')",
  "current_state = 'quarantined' AND normalized_target IN ('validation','maintenance','retired')",
  'A lifecycle transition reason is required',
  'FOR UPDATE',
  'record_system_audit',
  'trg_audit_platform_device_registry_changes',
  'REVOKE INSERT, UPDATE, DELETE ON public.platform_device_registry FROM authenticated',
  'REVOKE ALL ON FUNCTION public.register_platform_device',
  'REVOKE ALL ON FUNCTION public.transition_platform_device',
  'REVOKE ALL ON FUNCTION public.record_platform_device_heartbeat',
  'GRANT EXECUTE ON FUNCTION public.register_platform_device',
  'GRANT EXECUTE ON FUNCTION public.transition_platform_device',
  'GRANT EXECUTE ON FUNCTION public.record_platform_device_heartbeat(TEXT, TIMESTAMPTZ) TO service_role',
  "lifecycle_state NOT IN ('retired','quarantined')",
]) {
  if (!migration.includes(token)) throw new Error(`Device lifecycle security boundary missing: ${token}`);
}

if (!migration.includes("jsonb_typeof(COALESCE(_endpoint, '{}'::jsonb)) <> 'object'")) {
  throw new Error('Device endpoint configuration is not fail-closed');
}
if (!migration.includes("jsonb_typeof(COALESCE(_capabilities, '{}'::jsonb)) <> 'object'")) {
  throw new Error('Device capability configuration is not fail-closed');
}
if (!migration.includes("WHEN unique_violation THEN\n    RAISE EXCEPTION 'A platform device with this device key already exists'")) {
  throw new Error('Device registration idempotency/conflict boundary missing');
}
if (!migration.includes("_message_at > now() + interval '5 minutes'")) {
  throw new Error('Future-dated device heartbeat protection missing');
}

console.log('Next-gen device lifecycle boundary tests passed: admin onboarding, explicit state transitions, row locking, audit, direct-write lockdown, service heartbeat isolation, quarantine/retirement protection, and malformed configuration rejection are contractually wired.');
