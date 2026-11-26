import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'docs/engineering/migration-collision-20260912024500-schema-manifest-2026-11-26.json'), 'utf8'));
const [enterprisePath, globalPath] = manifest.candidates;
const enterprise = fs.readFileSync(path.join(root, enterprisePath), 'utf8');
const global = fs.readFileSync(path.join(root, globalPath), 'utf8');

function tableBody(sql, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = sql.match(new RegExp('CREATE TABLE IF NOT EXISTS public\\.' + escaped + ' \\(([\\s\\S]*?)\\n\\);'));
  if (!match) throw new Error('Expected CREATE TABLE IF NOT EXISTS for public.' + name);
  return match[1];
}
function columnNames(body) {
  return body.split(/\r?\n/).map(line => line.trim())
    .filter(line => line && !/^(CONSTRAINT|PRIMARY KEY|UNIQUE|CHECK|FOREIGN KEY)\b/i.test(line))
    .map(line => line.match(/^([a-z_][a-z0-9_]*)\s+/i)?.[1])
    .filter(Boolean);
}
for (const [table, expected] of Object.entries(manifest.shared_tables)) {
  const a = tableBody(enterprise, table);
  const b = tableBody(global, table);
  const aCols = new Set(columnNames(a));
  const bCols = new Set(columnNames(b));
  for (const col of expected.enterprise_only) {
    if (!aCols.has(col) || bCols.has(col)) throw new Error(table + ': enterprise-only column contract drift: ' + col);
  }
  for (const col of expected.global_only) {
    if (!bCols.has(col) || aCols.has(col)) throw new Error(table + ': global-only column contract drift: ' + col);
  }
  for (const col of aCols) if (!bCols.has(col) && !expected.enterprise_only.includes(col)) {
    throw new Error(table + ': unclassified enterprise-only column: ' + col);
  }
  for (const col of bCols) if (!aCols.has(col) && !expected.global_only.includes(col)) {
    throw new Error(table + ': unclassified global-only column: ' + col);
  }
}

const shapeTokens = [
  [enterprise, 'nursing_care_plans', 'created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT'],
  [global, 'nursing_care_plans', 'created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL'],
  [enterprise, 'nursing_care_plans', 'interventions TEXT,'],
  [global, 'nursing_care_plans', 'interventions TEXT NOT NULL'],
  [enterprise, 'nursing_shift_handovers', 'shift_date DATE NOT NULL'],
  [global, 'nursing_shift_handovers', 'ward_id UUID REFERENCES public.ward_units(id) ON DELETE SET NULL'],
  [enterprise, 'emergency_cases', "triage_priority TEXT NOT NULL DEFAULT 'urgent'"],
  [global, 'emergency_cases', "acuity TEXT NOT NULL DEFAULT 'urgent'"],
  [enterprise, 'theatre_cases', 'scheduled_at TIMESTAMPTZ,'],
  [global, 'theatre_cases', 'scheduled_start TIMESTAMPTZ NOT NULL'],
  [enterprise, 'transfusion_records', 'component TEXT NOT NULL'],
  [global, 'transfusion_records', 'blood_product TEXT NOT NULL']
];
for (const [source, table, token] of shapeTokens) {
  if (!tableBody(source, table).includes(token)) throw new Error(table + ': reviewed semantic-shape token drift: ' + token);
}

for (const name of manifest.distinct_table_families.enterprise_only) {
  if (!enterprise.includes('CREATE TABLE IF NOT EXISTS public.' + name + ' (')) throw new Error('Missing enterprise-only table: ' + name);
  if (global.includes('CREATE TABLE IF NOT EXISTS public.' + name + ' (')) throw new Error('Unexpected shared table: ' + name);
}
for (const name of manifest.distinct_table_families.global_only) {
  if (!global.includes('CREATE TABLE IF NOT EXISTS public.' + name + ' (')) throw new Error('Missing global-only table: ' + name);
  if (enterprise.includes('CREATE TABLE IF NOT EXISTS public.' + name + ' (')) throw new Error('Unexpected shared table: ' + name);
}

for (const policy of manifest.security_policy_names.enterprise) {
  if (!enterprise.includes('CREATE POLICY "' + policy + '"')) throw new Error('Missing enterprise RLS policy: ' + policy);
  if (global.includes('CREATE POLICY "' + policy + '"')) throw new Error('Unexpected shared enterprise policy: ' + policy);
}
for (const policy of manifest.security_policy_names.global) {
  if (!global.includes('CREATE POLICY "' + policy + '"')) throw new Error('Missing global RLS policy: ' + policy);
  if (enterprise.includes('CREATE POLICY "' + policy + '"')) throw new Error('Unexpected shared global policy: ' + policy);
}
for (const fn of manifest.functions.enterprise) if (!enterprise.includes('FUNCTION ' + fn + '(')) throw new Error('Missing enterprise function: ' + fn);
for (const fn of manifest.functions.global) if (!global.includes('FUNCTION ' + fn + '(')) throw new Error('Missing global function: ' + fn);

if (manifest.disposition.replay_authorized !== false ||
    manifest.disposition.automatic_merge !== 'prohibited' ||
    manifest.disposition.automatic_drop !== 'prohibited' ||
    manifest.disposition.automatic_dual_column_expansion !== 'prohibited') {
  throw new Error('Schema conflict manifest must retain non-destructive replay safeguards');
}
console.log('[migration-20260912024500-schema] PASS: 5 incompatible shared-table definitions and distinct table families match the reviewed evidence; replay remains blocked.');
