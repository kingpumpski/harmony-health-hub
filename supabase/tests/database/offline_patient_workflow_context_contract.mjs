import fs from 'node:fs';

const vitals = fs.readFileSync('supabase/migrations/20260914090000_offline_vitals_idempotency.sql','utf8');
const appointments = fs.readFileSync('supabase/migrations/20260914091000_offline_appointment_idempotency.sql','utf8');

for (const [name, source, required] of [
  ['offline vitals', vitals, [
    "IF _patient_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id)",
    "IF _appointment_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.appointments WHERE id = _appointment_id AND patient_id = _patient_id)",
    "has_role(auth.uid(),'admin')",
    "has_role(auth.uid(),'practitioner')",
    "has_role(auth.uid(),'nurse')",
    "has_role(auth.uid(),'midwife')"
  ]],
  ['offline appointments', appointments, [
    "IF _patient_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id)",
    "IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Scheduled time is required'; END IF;",
    "has_role(auth.uid(),'admin')",
    "has_role(auth.uid(),'practitioner')",
    "has_role(auth.uid(),'nurse')",
    "has_role(auth.uid(),'midwife')",
    "has_role(auth.uid(),'front_desk')"
  ]]
]) {
  for (const fragment of required) {
    if (!source.includes(fragment)) throw new Error(`${name}: missing ${fragment}`);
  }
}
console.log('Offline patient workflow authorization/context contract passed');
