#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
const p=path.join(process.cwd(),'supabase/migrations/20260929213000_harden_security_definer_mutation_paths_batch8.sql');
const sql=fs.readFileSync(p,'utf8').replace(/\s+/g,' ').trim().toLowerCase();
const signatures=[
'approve_diagnosis_import_batch(uuid)','approve_legacy_migration_batch(uuid)',
'create_ai_protocol_draft(text, text, integer, text)','create_data_migration_batch(text, text, text, text, text, integer)',
'create_reports_facility(text, text, text, text, text, text)','create_service_catalogue_item(text, text, text, text, numeric, text)',
'enter_lab_result(uuid, text, numeric, text, boolean)','grant_service_order_override(uuid, text)',
'import_approved_diagnosis_batch(uuid)','import_service_tariffs(text, jsonb)','import_stg_diagnoses(text, text, jsonb)',
'mark_billing_items_billed(uuid, uuid[])','mark_service_order_in_progress(uuid)'
];
for(const s of signatures){const q=`alter function public.${s} set search_path = pg_catalog, public;`;if(!sql.includes(q))throw new Error(`Missing: ${s}`);}
if(/set search_path = public\s*;/i.test(sql))throw new Error('Unsafe public-only search_path');
console.log(`Verified ${signatures.length} SECURITY DEFINER mutation/import hardening statements.`);
