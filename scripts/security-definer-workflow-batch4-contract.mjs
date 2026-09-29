import fs from 'node:fs';
const m=fs.readFileSync('supabase/migrations/20260929183000_harden_security_definer_workflow_paths_batch4.sql','utf8');
const signatures=[
'create_dental_record(uuid, text, text, text)','create_discharge_insurance_claim(uuid, text, text)',
'create_lab_test_catalogue_item(text, text, text, text, text, numeric, numeric, text, numeric, integer)',
'create_ophthalmology_exam(uuid, text, text, text, numeric, text, text)',
'create_patient_appointment(uuid, timestamptz, text, text)',
'create_pharmacy_inventory_item(text, text, text, text, text, text, text, date, integer, integer, numeric)',
'create_pharmacy_pos_sale(uuid, uuid, integer)',
'create_service_order(uuid, uuid, text, text, numeric, uuid, text, uuid, uuid, uuid, text, text)',
'create_staff_shift_assignment(uuid, text, text, timestamptz, timestamptz)',
'create_theatre_case(uuid, text, timestamptz, text, text, uuid, uuid, uuid)',
'create_transfusion_record(uuid, text, text, text, boolean, uuid)',
'create_walk_in_billable_service(uuid, text, integer, text)',
'create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb)',
'end_video_session(uuid)','enqueue_external_notification_channels(uuid)'
];
for(const s of signatures) if(!m.includes('public.'+s)) throw new Error('Missing '+s);
if((m.match(/set search_path = pg_catalog, public/g)||[]).length!==signatures.length) throw new Error('Search-path hardening count mismatch');
console.log('Batch 4 SECURITY DEFINER workflow contract passed.');
