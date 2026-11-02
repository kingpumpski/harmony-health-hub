#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
const p=path.join(process.cwd(),'supabase/migrations/20260929213000_harden_security_definer_mutation_paths_batch8.sql');
const sql=fs.readFileSync(p,'utf8').replace(/\s+/g,' ').trim().toLowerCase();
const signatures=[
'public.approve_diagnosis_import_batch(uuid)','public.approve_legacy_migration_batch(uuid)',
'public.create_ai_protocol_draft(text, text, integer, text)','public.create_data_migration_batch(text, text, text, text, text, integer)',
'public.create_reports_facility(text, text, text, text, text, text)','public.create_service_catalogue_item(text, text, text, text, numeric, text)',
'public.enter_lab_result(uuid, text, numeric, text, boolean)','public.grant_service_order_override(uuid, text)',
'public.import_approved_diagnosis_batch(uuid)','public.import_service_tariffs(text, jsonb)','public.import_stg_diagnoses(text, text, jsonb)',
'public.mark_billing_items_billed(uuid, uuid[])','public.mark_service_order_in_progress(uuid)'
];
for(const signature of signatures){if(!sql.includes("('"+signature+"')"))throw new Error('Missing guarded function signature: '+signature);}
for(const required of [
'do $batch8_mutation_function_paths$',
'pg_catalog.to_regprocedure(v_signature)',
'p.proconfig',
"format( 'alter function %s set search_path = pg_catalog, public', v_function )",
"not coalesce(v_config @> array['search_path=\"\"']"
]) {
 if(!sql.includes(required)) throw new Error('Missing Batch8 replay-safe hardening control: '+required);
}
if(/set search_path = public\s*;/i.test(sql))throw new Error('Unsafe public-only search_path');
console.log('Verified '+signatures.length+' guarded SECURITY DEFINER mutation/import hardening targets.');
