import fs from 'node:fs';
const m=fs.readFileSync('supabase/migrations/20260929180000_harden_clinical_financial_security_definer_search_paths_batch2.sql','utf8');
const fns=['activate_patient_visit_coverage','adjust_invoice_item_tariff','cancel_service_order','complete_encounter_workflow','create_encounter_workflow','create_imaging_order_with_payment_gate','create_lab_order_with_payment_gate','create_nursing_note','create_patient_referral_workflow','create_procedure_note'];
for(const fn of fns) if(!m.includes('public.'+fn+'(')) throw new Error('Missing '+fn);
if((m.match(/set search_path = pg_catalog, public/g)||[]).length!==fns.length) throw new Error('Every function must harden search_path');
console.log('Batch 2 SECURITY DEFINER search-path contract passed.');
