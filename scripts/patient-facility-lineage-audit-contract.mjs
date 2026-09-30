#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = process.cwd();
const migrations = fs.readdirSync(path.join(root, 'supabase/migrations'))
  .filter((n) => n.endsWith('.sql'))
  .sort();
const source = migrations.map((n) => fs.readFileSync(path.join(root, 'supabase/migrations', n), 'utf8')).join('\n');

const compact = (v) => v.replace(/--.*$/gm, '').replace(/\s+/g, ' ').toLowerCase();

const targets = {
  create_ai_clinical_session: 'create_ai_clinical_session(uuid,text,jsonb,jsonb)',
  create_lab_order_with_payment_gate: 'create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid)',
  create_imaging_order_with_payment_gate: 'create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric)',
  create_insurance_claim_draft: 'create_insurance_claim_draft(uuid,text,text,numeric,uuid)',
  create_pharmacy_pos_sale: 'create_pharmacy_pos_sale(uuid,uuid,integer)',
  update_patient_workflow: 'update_patient_workflow(uuid,jsonb)',
  upload_patient_document_metadata: 'upload_patient_document_metadata(uuid,text,text,text,text,bigint,text)',
  search_patient_directory: 'search_patient_directory(text,integer)',
};

const s = compact(source);

for (const [name, signature] of Object.entries(targets)) {
  const fn = 'public.' + signature;
  assert.ok(s.includes('revoke all on function ' + fn + ' from public, anon;'),
    fn + ': PUBLIC/anon execution must be explicitly revoked');
  assert.ok(s.includes('grant execute on function ' + fn + ' to authenticated;'),
    fn + ': authenticated execution must be explicit');
}

function bodyAfterDeclaration(name) {
  const re = new RegExp('create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.' + name.replace(/[.*+?^$()|[\\]\\\\]/g,'\\$&') + '\\s*\\(', 'i');
  const m = re.exec(source);
  assert.ok(m, name + ': declaration not found');
  return source.slice(m.index, m.index + 14000);
}

const patientScoped = [
  'create_ai_clinical_session',
  'create_lab_order_with_payment_gate',
  'create_imaging_order_with_payment_gate',
  'create_insurance_claim_draft',
  'create_pharmacy_pos_sale',
  'update_patient_workflow',
  'upload_patient_document_metadata',
  'search_patient_directory',
];

const facilityEvidence = [
  'current_user_facility_id',
  'has_facility_access',
  'facility_id',
  'patient_facilities',
  'patient_facility',
];

for (const name of patientScoped) {
  const body = bodyAfterDeclaration(name).toLowerCase();
  const hasLineage = facilityEvidence.some((term) => body.includes(term));
  if (!hasLineage) {
    console.warn('[patient-facility-gate] ' + name + ': no facility-lineage predicate found in the first function body window; keep this RPC blocked from tenancy sign-off until explicit two-facility evidence exists.');
  }
}

console.log('[patient-facility-gate] high-risk RPC privilege and tenancy-evidence scan completed.');
