import fs from 'node:fs';

const root = process.cwd();
const migration = fs.readFileSync(`${root}/supabase/migrations/20260916190000_nextgen_medication_pharmacy_safety_concurrency.sql`, 'utf8');
const marFoundation = fs.readFileSync(`${root}/supabase/migrations/20260912023000_global_medication_administration.sql`, 'utf8');
const pharmacyAuthority = fs.readFileSync(`${root}/supabase/migrations/20260914141000_pharmacy_lifecycle_server_authority.sql`, 'utf8');
const workflowSecurity = fs.readFileSync(`${root}/supabase/migrations/20260912032000_global_hims_secure_workflows.sql`, 'utf8');
const reconciliation = fs.readFileSync(`${root}/supabase/migrations/20260912190000_module_workflow_reconciliation.sql`, 'utf8');
const hardening = fs.readFileSync(`${root}/supabase/migrations/20260914170000_clinical_triage_medication_mutation_hardening.sql`, 'utf8');

const checks = [
  ['MAR foundation exists', marFoundation.includes('CREATE TABLE IF NOT EXISTS public.medication_administrations')],
  ['Existing secure MAR workflow exists', workflowSecurity.includes('CREATE OR REPLACE FUNCTION public.transition_medication_administration')],
  ['Existing pharmacy server authority exists', pharmacyAuthority.includes('CREATE OR REPLACE FUNCTION public.confirm_pharmacy_dispense')],
  ['Existing MAR reconciliation exists', reconciliation.includes('CREATE OR REPLACE FUNCTION public.reopen_medication_administration')],
  ['Existing direct MAR mutation lockdown exists', hardening.includes('REVOKE INSERT, UPDATE, DELETE ON public.medication_administrations FROM authenticated')],
  ['MAR integrity trigger exists', migration.includes('guard_medication_administration_integrity') && migration.includes('t_mar_integrity_guard')],
  ['Administered state requires actor and timestamp', migration.includes("NEW.status = 'administered'") && migration.includes('NEW.administered_by IS NULL OR NEW.administered_at IS NULL')],
  ['Held/refused/omitted require reason', migration.includes("NEW.status IN ('held','refused','omitted')") && migration.includes('requires a documented reason')],
  ['Scheduled state cannot retain administering actor', migration.includes("NEW.status = 'scheduled' AND NEW.administered_by IS NOT NULL")],
  ['Medication transition row locks record', migration.includes('FROM public.medication_administrations') && migration.includes('FOR UPDATE')],
  ['Medication timing window is enforced', migration.includes('due_window_minutes') && migration.includes('outside its permitted administration window')],
  ['Witness cannot self-witness', migration.includes('_witnessed_by=auth.uid()')],
  ['Witness must be authorized clinical user', migration.includes('Witness must be an authorized clinical user')],
  ['Medication transitions are audited', migration.includes("medication_administration_'||_status") && migration.includes('record_system_audit')],
  ['Reopen requires explicit reason', migration.includes('professional reason is required to reopen')],
  ['Reopen row locks record', migration.includes('Only a closed documented medication record can be reopened') && migration.includes('WHERE id=_record_id FOR UPDATE')],
  ['Reopen clears prior administration attribution', migration.includes("status='scheduled'") && migration.includes('administered_at=NULL') && migration.includes('administered_by=NULL')],
  ['Reopen is audited', migration.includes("medication_administration_reopened")],
  ['Pharmacy stock non-negative guard exists', migration.includes('guard_pharmacy_inventory_nonnegative') && migration.includes('Pharmacy stock cannot be negative')],
  ['Pharmacy dispensing row locks plan', migration.includes('FROM public.pharmacy_dispensing_plans WHERE id=_plan_id FOR UPDATE')],
  ['Pharmacy dispensing row locks order', migration.includes('FROM public.service_orders WHERE id=p.service_order_id FOR UPDATE')],
  ['Pharmacy dispensing row locks inventory', migration.includes('FROM public.pharmacy_inventory WHERE id=p.inventory_id FOR UPDATE')],
  ['Pharmacy payment gate remains enforced', migration.includes("order_status NOT IN('released','in_progress')")],
  ['Closed encounters cannot dispense', migration.includes("encounter_status IN('completed','cancelled')")],
  ['Conditional stock decrement prevents race', migration.includes('WHERE id=i.id AND stock_quantity>=p.prepared_quantity') && migration.includes('Stock changed concurrently; retry dispensing')],
  ['Dispensing plan update is conditional', migration.includes("WHERE id=p.id AND status='unpaid'")],
  ['Terminal pharmacy response is idempotent', migration.includes("IF p.status='dispensed' THEN") && migration.includes("'idempotent',true")],
  ['Pharmacy dispensing is audited', migration.includes("'pharmacy_dispensed'") && migration.includes('record_system_audit')],
  ['Direct MAR/pharmacy mutations revoked', migration.includes('REVOKE INSERT,UPDATE,DELETE ON TABLE public.medication_administrations,public.pharmacy_dispensing_plans,public.pharmacy_pos_sales,public.pharmacy_inventory FROM authenticated')],
  ['Authenticated execution is explicitly granted', migration.includes('GRANT EXECUTE ON FUNCTION public.transition_medication_administration') && migration.includes('GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_dispense')],
];

const failures = checks.filter(([, ok]) => !ok);
if (failures.length) {
  console.error(`Medication/pharmacy safety contract failed: ${failures.length} checks`);
  for (const [name] of failures) console.error(`- ${name}`);
  process.exit(1);
}

console.log(`Medication/pharmacy safety contract passed: ${checks.length} checks`);
