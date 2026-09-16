import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260916160000_nextgen_lab_device_result_reconciliation.sql', 'utf8');
const deviceBoundary = fs.readFileSync('supabase/migrations/20260916150000_nextgen_device_integration_boundary.sql', 'utf8');
const clinicalWorkflow = fs.readFileSync('supabase/migrations/20260912203000_clinical_module_workflow_security.sql', 'utf8');

const required = [
  ['QC ledger', 'CREATE TABLE IF NOT EXISTS public.lab_result_qc_checks'],
  ['QC RLS', 'ALTER TABLE public.lab_result_qc_checks ENABLE ROW LEVEL SECURITY'],
  ['QC authorization', "public.has_role(auth.uid(),'lab_technician')"],
  ['QC pass/fail boundary', "_status NOT IN ('passed','failed')"],
  ['device message linkage', 'integration_message_id UUID REFERENCES public.platform_integration_messages'],
  ['lab order lock', 'FROM public.lab_orders WHERE id = _lab_order_id FOR UPDATE'],
  ['message lock', 'FROM public.platform_integration_messages\n  WHERE id = _integration_message_id'],
  ['ASTM/HL7 restriction', "v_message.standard NOT IN ('ASTM','HL7_V2')"],
  ['sample lifecycle gate', "v_order.status NOT IN ('sample_collected','in_progress')"],
  ['patient reconciliation', 'v_message.patient_reference <> v_order.patient_id::TEXT'],
  ['QC finalization gate', "v_qc.status <> 'passed'"],
  ['catalogue validation', 'v_catalog.id IS NULL OR NOT v_catalog.active'],
  ['canonical result insertion', 'INSERT INTO public.lab_results'],
  ['order completion', "SET status = 'completed', updated_at = now()"],
  ['delivery acknowledgement', "SET lifecycle_state = 'delivered'"],
  ['authenticated direct result lockdown', 'REVOKE INSERT, UPDATE, DELETE ON public.lab_results FROM authenticated'],
  ['public execute revoked', 'REVOKE ALL ON FUNCTION public.reconcile_device_lab_result'],
  ['authenticated execution', 'GRANT EXECUTE ON FUNCTION public.reconcile_device_lab_result'],
];

for (const [label, needle] of required) {
  if (!migration.includes(needle)) throw new Error(`Missing ${label}: ${needle}`);
}

if (!deviceBoundary.includes('accept_device_integration_message')) throw new Error('Device intake boundary missing');
if (!deviceBoundary.includes("lifecycle_state = 'queued'")) throw new Error('Device intake does not queue transport');
if (deviceBoundary.includes('INSERT INTO public.lab_results')) throw new Error('Device transport boundary must not create canonical lab results');
if (!clinicalWorkflow.includes('collect_lab_sample')) throw new Error('Canonical laboratory sample collection boundary missing');
if (!clinicalWorkflow.includes('approve_lab_result')) throw new Error('Canonical laboratory approval boundary missing');

console.log('next-gen laboratory device reconciliation contract checks passed');
