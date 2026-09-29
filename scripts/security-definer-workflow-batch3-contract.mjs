import fs from 'node:fs';
const m=fs.readFileSync('supabase/migrations/20260929181500_harden_security_definer_workflow_paths_batch3.sql','utf8');
const signatures=[
'acknowledge_nursing_handover(uuid)','claim_appointment(uuid)','collect_lab_sample(uuid)',
'complete_service_order(uuid)','confirm_pharmacy_pos_sale(uuid)',
'create_appointment_workflow(uuid, timestamptz, text, text)',
'create_appointment_workflow(uuid, timestamptz, text, text, text, uuid)',
'create_care_transition_workflow(uuid, text, text, text, boolean, boolean, date, text)',
'create_emergency_case(uuid, text, text, text, uuid)',
'create_fertility_cycle_workflow(uuid, text, text, date, text)',
'create_maternity_episode_workflow(uuid, integer, integer, date, date, text, text, text)',
'create_nursing_care_plan(uuid, text, text, text, text, uuid, uuid)',
'create_nursing_shift_handover(uuid, text, text, text, text, boolean, uuid)'
];
for(const s of signatures) if(!m.includes('public.'+s)) throw new Error('Missing '+s);
if((m.match(/set search_path = pg_catalog, public/g)||[]).length!==signatures.length) throw new Error('Search-path hardening count mismatch');
console.log('Batch 3 SECURITY DEFINER workflow contract passed.');
