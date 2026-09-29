#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const migrationPath = path.join(process.cwd(), 'supabase', 'migrations', '20260929203000_harden_security_definer_read_workspace_paths_batch6.sql');
const sql = fs.readFileSync(migrationPath, 'utf8');

const signatures = [
  'get_admission_workspace(integer)',
  'get_appointment_worklist(integer)',
  'get_attending_patient_history(uuid, uuid)',
  'get_department_queue(text, integer)',
  'get_emergency_workspace(integer)',
  'get_encounter_clinical_context(uuid, uuid)',
  'get_imaging_workspace(integer)',
  'get_laboratory_workspace(integer)',
  'get_maternity_workspace(integer, uuid)',
  'get_patient_admission_history(uuid)',
  'get_patient_directory_record(uuid)',
  'get_patient_hub_clinical_snapshot(uuid)',
  'get_patient_invoices(uuid, integer)',
  'get_pharmacy_workspace(integer)',
];

for (const signature of signatures) {
  const escaped = signature.replace(/[.*+?^$\\{}()|[\\]\\]/g, '\\$&');
  const pattern = new RegExp(
    `ALTER\\s+FUNCTION\\s+public\\.${escaped}\\s+SET\\s+search_path\\s*=\\s*pg_catalog\\s*,\\s*public\\s*;`,
    'i',
  );
  if (!pattern.test(sql)) {
    throw new Error(`Missing hardened ALTER FUNCTION for ${signature}`);
  }
}

if (/SET\\s+search_path\\s*=\\s*public\\s*;/i.test(sql)) {
  throw new Error('Migration contains an unsafe public-only search_path');
}

console.log(`Verified ${signatures.length} SECURITY DEFINER read/workspace hardening statements.`);
