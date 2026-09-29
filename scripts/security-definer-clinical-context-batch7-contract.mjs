#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
const p=path.join(process.cwd(),'supabase/migrations/20260929204500_harden_security_definer_clinical_context_paths_batch7.sql');
const sql=fs.readFileSync(p,'utf8').replace(/\s+/g,' ').trim().toLowerCase();
const signatures=[
'get_ai_clinical_context(uuid)','get_encounter_workflow_workspace()','get_patient_appointments(uuid, integer)',
'get_patient_bmi_context(uuid)','patient_coverage_details(uuid)','record_patient_deposit(uuid, numeric, text)',
'save_encounter_draft(uuid, text, text, text)','schedule_medication_administration(uuid, text, text, text, timestamptz, text, integer)',
'search_patient_directory(text, integer)','start_appointment_encounter(uuid, text, text)',
'transition_medication_administration(uuid, text, text, text, uuid)'
];
for(const s of signatures){const q=`alter function public.${s} set search_path = pg_catalog, public;`;if(!sql.includes(q))throw new Error(`Missing: ${s}`);}
if(/set search_path = public\s*;/i.test(sql))throw new Error('Unsafe public-only search_path');
console.log(`Verified ${signatures.length} clinical SECURITY DEFINER hardening statements.`);
