import fs from 'node:fs';
const m=fs.readFileSync('supabase/migrations/20260929184500_harden_security_definer_auth_helper_paths_batch5.sql','utf8');
const signatures=['can_edit_patient_record(uuid)','claim_notification_queue(integer)','current_user_can_edit_patient_record()','current_user_facility_id()','current_user_has_catalogue_create_permission(text)','current_user_has_facility_access(uuid)','current_user_has_role(app_role)','current_user_is_clinical_staff()'];
for(const s of signatures) if(!m.includes('public.'+s)) throw new Error('Missing '+s);
if((m.match(/set search_path = pg_catalog, public/g)||[]).length!==signatures.length) throw new Error('Search-path hardening count mismatch');
console.log('Batch 5 SECURITY DEFINER authorization helper contract passed.');
