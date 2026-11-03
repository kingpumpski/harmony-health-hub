#!/usr/bin/env node
import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/20260929224500_harden_security_definer_internal_trigger_paths_batch12.sql','utf8').replace(/\s+/g,' ').trim().toLowerCase();
const signatures=["public.audit_operational_row_change()","public.audit_patient_change()","public.audit_patient_changes()","public.fanout_notification_after_insert()","public.generate_patient_code()","public.handle_new_user()","public.has_active_patient_visit_coverage(uuid)","public.has_facility_access(uuid,uuid)","public.is_clinical_staff(uuid)","public.lock_overdue_medication_slots()","public.notify_due_medications()","public.notify_insurance_claim_lifecycle()","public.record_system_audit(text,text,text,uuid,text,jsonb)","public.service_order_event_trigger()","public.set_ward_facility_context()","public.validate_service_order_encounter()"];
for(const signature of signatures){if(!sql.includes("('"+signature+"')"))throw new Error('Missing guarded function signature: '+signature);}
for(const required of [
'do $batch12_internal_trigger_paths$',
'pg_catalog.to_regprocedure(v_signature)',
'p.proconfig',
"format( 'alter function %s set search_path = pg_catalog, public', v_function )",
"not coalesce(v_config @> array['search_path=\"\"']"
]) {
 if(!sql.includes(required))throw new Error('Missing replay-safe hardening control: '+required);
}
console.log('Verified '+signatures.length+' guarded SECURITY DEFINER hardening targets.');
