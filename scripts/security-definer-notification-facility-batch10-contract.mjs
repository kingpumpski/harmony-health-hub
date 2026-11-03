#!/usr/bin/env node
import fs from 'node:fs';

const sql=fs.readFileSync('supabase/migrations/20260929221500_harden_security_definer_notification_facility_paths_batch10.sql','utf8').replace(/\s+/g,' ').trim().toLowerCase();
const signatures=[
'public.enqueue_notification_v2(text,uuid,jsonb,text,jsonb,text,timestamp with time zone,text,uuid,text,text,uuid)',
'public.ensure_notification_preferences(uuid)',
'public.erase_notification_history(uuid)',
'public.initialize_facility_notification_onboarding(uuid)',
'public.mark_facility_notification_production_ready(uuid)',
'public.mark_notification_read(uuid)',
'public.mark_report_submissions_submitted(uuid[])',
'public.mark_video_session_paid(uuid)',
'public.record_notification_consent(text,text,boolean,text,text,inet)',
'public.recover_stale_report_run(uuid,integer)',
'public.register_notification_device(text,text,text,text)',
'public.revoke_notification_device(text)',
'public.seed_facility_reports(uuid)',
'public.set_facility_routing_mode(text)',
'public.set_my_active_facility(uuid)',
'public.sync_overdue_report_submissions(uuid,date,date)',
'public.upsert_my_staff_signature(text)',
'public.upsert_report_submission_tracking(uuid,uuid,date,date,date,jsonb)',
'public.verify_facility_notification_provider(uuid,text,text,boolean,text)'
];
for(const signature of signatures){if(!sql.includes("('"+signature+"')"))throw new Error('Missing guarded Batch10 signature: '+signature);}
for(const required of [
'do $batch10_notification_facility_paths$',
'pg_catalog.to_regprocedure(v_signature)',
'p.proconfig',
"format( 'alter function %s set search_path = pg_catalog, public', v_function )",
"not coalesce(v_config @> array['search_path=\"\"']"
]) {
 if(!sql.includes(required))throw new Error('Missing Batch10 replay-safe hardening control: '+required);
}
console.log('Verified '+signatures.length+' guarded notification/facility SECURITY DEFINER hardening targets.');
