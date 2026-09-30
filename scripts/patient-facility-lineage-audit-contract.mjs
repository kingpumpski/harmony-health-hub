#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = process.cwd();
const migrationDir = path.join(root, 'supabase/migrations');
const migrations = fs.readdirSync(migrationDir)
  .filter((n) => n.endsWith('.sql'))
  .sort();

const files = migrations.map((name) => ({
  name,
  source: fs.readFileSync(path.join(migrationDir, name), 'utf8'),
}));
const source = files.map(({ source }) => source).join('\n');
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
  assert.ok(
    s.includes('revoke all on function ' + fn + ' from public, anon;'),
    fn + ': PUBLIC/anon execution must be explicitly revoked',
  );
  assert.ok(
    s.includes('grant execute on function ' + fn + ' to authenticated;'),
    fn + ': authenticated execution must be explicit',
  );
}

function declarationRegex(name) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, '\\$&');
  return new RegExp(
    'create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.' +
      escaped +
      '\\s*\\(',
    'gi',
  );
}

function latestDeclaration(name) {
  const re = declarationRegex(name);
  let match;
  let latest = null;
  while ((match = re.exec(source)) !== null) {
    latest = match;
  }
  assert.ok(latest, name + ': declaration not found');
  return source.slice(latest.index, latest.index + 20000);
}

const tenancyAssertions = [
  'public.hms_assert_patient_facility_access(',
  'public.hms_patient_has_facility_access(',
];

const resourceLineagePatterns = [
  /public\\.has_facility_access\\s*\\(/i,
  /public\\.current_user_facility_id\\s*\\(/i,
  /public\\.hms_current_active_facility_id\\s*\\(/i,
];

for (const [name] of Object.entries(targets)) {
  const body = latestDeclaration(name);
  const normalized = body.toLowerCase();

  const explicitPatientTenancy = tenancyAssertions.some((term) => normalized.includes(term));
  const explicitResourceFacility = resourceLineagePatterns.some((pattern) => pattern.test(body));

  if (!explicitPatientTenancy && !explicitResourceFacility) {
    throw new Error(
      '[patient-facility-gate] ' +
        name +
        ': latest migration definition has no executable patient/facility tenancy predicate. ' +
        'A generic facility_id token is insufficient. Implement explicit patient access or resource facility lineage, ' +
        'then validate with two non-admin users in two facilities before tenancy sign-off.',
    );
  }
}

console.log(
  '[patient-facility-gate] high-risk RPC privilege and latest-definition tenancy-evidence scan completed.',
);
