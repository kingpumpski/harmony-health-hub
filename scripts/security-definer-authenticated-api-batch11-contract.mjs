#!/usr/bin/env node
import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/20260929223000_harden_security_definer_authenticated_api_paths_batch11.sql','utf8').replace(/\s+/g,' ').trim().toLowerCase();
const signatures=["public.find_legacy_patient_candidates(uuid)","public.find_pharmacy_alternatives(text,text)","public.get_ai_case_memory_for_diagnosis(text,integer)","public.get_ai_report_requests(uuid,integer)","public.get_appointment_clinician()","public.get_appointment_clinicians()","public.get_current_facility_context()","public.get_it_support_system_logs(text,text,integer)","public.get_legacy_patient_candidates(uuid)","public.get_missing_billing_tariffs(uuid)","public.get_my_permissions()","public.get_pending_specialist_referrals()","public.get_staff_signature_for_report(uuid)","public.get_workflow_notifications(integer)","public.notification_feature_enabled(text,uuid)","public.promote_legacy_migration_batch(uuid)","public.reconcile_legacy_migration_row(uuid,uuid,numeric,text)","public.reconcile_legacy_record_patient(uuid,uuid,text)","public.record_ai_clinical_event(uuid,text,jsonb)","public.reopen_own_document(text,uuid)","public.replace_role_permissions(public.app_role,text[])","public.set_facility_notification_provider(uuid,text,text,text,text,text,text,jsonb)","public.set_facility_notification_provider(uuid,text,text,text,text,text,text)","public.set_staff_shift_assignment_active(uuid,boolean)","public.stage_data_migration_rows(uuid,jsonb)","public.transition_ai_protocol(uuid,text)","public.validate_diagnosis_import_batch(uuid)","public.validate_legacy_migration_batch(uuid)","public.validate_legacy_record(uuid)"];
for(const signature of signatures){if(!sql.includes("('"+signature+"')"))throw new Error('Missing guarded function signature: '+signature);}
for(const required of [
'do $batch11_authenticated_api_paths$',
'pg_catalog.to_regprocedure(v_signature)',
'p.proconfig',
"format( 'alter function %s set search_path = pg_catalog, public', v_function )",
"not coalesce(v_config @> array['search_path=\"\"']"
]) {
 if(!sql.includes(required))throw new Error('Missing replay-safe hardening control: '+required);
}
console.log('Verified '+signatures.length+' guarded SECURITY DEFINER hardening targets.');
