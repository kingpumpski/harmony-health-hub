import fs from 'node:fs';

const root = process.cwd();
const migration = fs.readFileSync(`${root}/supabase/migrations/20260916192000_nextgen_transfusion_safety_concurrency.sql`, 'utf8');
const existing = fs.readFileSync(`${root}/supabase/migrations/20260914140000_theatre_emergency_transfusion_lifecycle_hardening.sql`, 'utf8');
const consent = fs.readFileSync(`${root}/supabase/migrations/20260913100000_transfusion_consent_hardening.sql`, 'utf8');

const checks = [
  ['Existing transfusion lifecycle is preserved', existing.includes('CREATE OR REPLACE FUNCTION public.record_transfusion_event')],
  ['Existing consent gate is preserved', consent.includes('Documented transfusion consent must be confirmed before scheduling')],
  ['Transfusion integrity trigger exists', migration.includes('guard_transfusion_record_integrity') && migration.includes('t_transfusion_integrity_guard')],
  ['Consent remains required for active/completed states', migration.includes("NEW.status IN ('issued','running','completed','stopped')") && migration.includes('NEW.consent_confirmed IS NOT TRUE')],
  ['Blood-unit identifier is required before running', migration.includes("NEW.status IN ('running','completed','stopped')") && migration.includes('NEW.unit_identifier')],
  ['Reaction requires documentation', migration.includes('NEW.reaction_observed IS TRUE') && migration.includes('A transfusion reaction requires clinical documentation')],
  ['Lifecycle function uses row lock', migration.includes('FROM public.transfusion_records WHERE id=_record_id FOR UPDATE')],
  ['Closed records cannot be reopened', migration.includes('Closed transfusion record cannot be reopened or changed')],
  ['Terminal same-state call is idempotent', migration.includes("IF _status=r.status THEN") && migration.includes("'idempotent',true")],
  ['Issued can only move to running or cancelled', migration.includes("WHEN 'issued' THEN _status IN ('running','cancelled')")],
  ['Running can only move to completed or stopped', migration.includes("WHEN 'running' THEN _status IN ('completed','stopped')")],
  ['Closed encounter is protected', migration.includes("encounter_status='cancelled'") && migration.includes("encounter_status='completed'")],
  ['Runtime reaction gate is enforced', migration.includes('Transfusion reaction requires clinical documentation')],
  ['Reaction event is audited', migration.includes("'transfusion_'||_status") && migration.includes('record_system_audit')],
  ['Direct transfusion mutation is revoked', migration.includes('REVOKE INSERT,UPDATE,DELETE ON public.transfusion_records FROM authenticated')],
  ['Authenticated lifecycle execution is explicit', migration.includes('GRANT EXECUTE ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) TO authenticated')],
];

const failures = checks.filter(([, ok]) => !ok);
if (failures.length) {
  console.error(`Transfusion safety contract failed: ${failures.length} checks`);
  for (const [name] of failures) console.error(`- ${name}`);
  process.exit(1);
}
console.log(`Transfusion safety contract passed: ${checks.length} checks`);
