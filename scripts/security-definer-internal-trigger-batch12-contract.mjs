#!/usr/bin/env node
import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/20260929224500_harden_security_definer_internal_trigger_paths_batch12.sql','utf8').toLowerCase();
const signatures=["audit_operational_row_change()","audit_patient_change()","audit_patient_changes()","fanout_notification_after_insert()","generate_patient_code()","handle_new_user()","has_active_patient_visit_coverage(uuid)","has_facility_access(uuid,uuid)","is_clinical_staff(uuid)","lock_overdue_medication_slots()","notify_due_medications()","notify_insurance_claim_lifecycle()","record_system_audit(text,text,text,uuid,text,jsonb)","service_order_event_trigger()","set_ward_facility_context()","validate_service_order_encounter()"];
for(const s of signatures)if(!sql.includes('alter function public.'+s+' set search_path = pg_catalog, public;'))throw new Error('Missing '+s);
console.log('Verified '+signatures.length+' internal/trigger SECURITY DEFINER path hardening statements.');
