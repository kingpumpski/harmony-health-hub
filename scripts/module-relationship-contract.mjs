import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('src/integrations/supabase/types.ts', 'utf8');
const exceptionDocument = JSON.parse(fs.readFileSync('scripts/module-relationship-exceptions.json', 'utf8'));
const tablePattern = /^      ([a-z][a-z0-9_]*): \{\n        Row: \{\n([\s\S]*?)\n        \}\n        Insert:/gm;
const tables = new Map();

for (const match of source.matchAll(tablePattern)) {
  const remaining = source.slice(match.index + match[0].length);
  const nextTable = remaining.search(/\n      [a-z][a-z0-9_]*: \{/);
  const tableBlock = source.slice(match.index, nextTable < 0 ? source.length : match.index + match[0].length + nextTable);
  const columns = new Set([...match[2].matchAll(/^          ([a-z][a-z0-9_]*):/gm)].map((item) => item[1]));
  const relationships = [];
  const relationshipText = tableBlock.match(/Relationships: \[([\s\S]*?)\n        \]/)?.[1] ?? '';
  const relationshipPattern = /foreignKeyName: "([^"]+)"[\s\S]*?columns: \[([^\]]+)\][\s\S]*?referencedRelation: "([^"]+)"[\s\S]*?referencedColumns: \[([^\]]+)\]/g;
  for (const relation of relationshipText.matchAll(relationshipPattern)) {
    relationships.push({
      name: relation[1],
      columns: [...relation[2].matchAll(/"([^"]+)"/g)].map((item) => item[1]),
      target: relation[3],
      targetColumns: [...relation[4].matchAll(/"([^"]+)"/g)].map((item) => item[1]),
    });
  }
  tables.set(match[1], { columns, relationships });
}
assert.ok(tables.size >= 150, 'expected complete generated public table types; found ' + tables.size);

const expected = [
  ['appointments','patient_id','patients','id'],
  ['encounters','patient_id','patients','id'],
  ['encounters','appointment_id','appointments','id'],
  ['admissions','patient_id','patients','id'],
  ['admissions','encounter_id','encounters','id'],
  ['ward_beds','ward_id','ward_units','id'],
  ['nursing_shift_handovers','patient_id','patients','id'],
  ['nursing_shift_handovers','facility_id','healthcare_facilities','id'],
  ['emergency_cases','patient_id','patients','id'],
  ['theatre_cases','patient_id','patients','id'],
  ['transfusion_records','patient_id','patients','id'],
  ['lab_orders','patient_id','patients','id'],
  ['lab_results','lab_order_id','lab_orders','id'],
  ['imaging_orders','patient_id','patients','id'],
  ['prescriptions','patient_id','patients','id'],
  ['medication_administrations','patient_id','patients','id'],
  ['medication_administrations','prescription_id','prescriptions','id'],
  ['invoices','patient_id','patients','id'],
  ['invoice_items','invoice_id','invoices','id'],
  ['payments','invoice_id','invoices','id'],
  ['insurance_claims','invoice_id','invoices','id'],
  ['payroll_items','payroll_period_id','payroll_periods','id'],
  ['payroll_items','employee_id','hr_employees','id'],
  ['patient_referrals','patient_id','patients','id'],
  ['care_transitions','patient_id','patients','id'],
  ['fertility_cycles','patient_id','patients','id'],
  ['fertility_monitoring','cycle_id','fertility_cycles','id'],
  ['video_sessions','appointment_id','appointments','id'],
  ['ward_beds','admission_id','admissions','id'],
];

const exceptions = new Map(exceptionDocument.exceptions.map((item) => [
  [item.table,item.column,item.target,item.referencedColumn].join('|'), item,
]));
assert.equal(exceptions.size, exceptionDocument.exceptions.length, 'relationship exception registry contains duplicates');

const failures = [];
const knownGaps = [];
let verified = 0;
for (const [table,column,target,referencedColumn] of expected) {
  const key = [table,column,target,referencedColumn].join('|');
  const definition = tables.get(table);
  if (!definition) {
    failures.push('missing generated table ' + table);
    continue;
  }
  if (!definition.columns.has(column)) {
    failures.push(table + ' is missing relationship column ' + column);
    continue;
  }
  const present = definition.relationships.some((relation) =>
    relation.columns.length === 1 && relation.columns[0] === column &&
    relation.target === target && relation.targetColumns.length === 1 &&
    relation.targetColumns[0] === referencedColumn
  );
  if (present) {
    verified += 1;
    if (exceptions.has(key)) failures.push('stale exception: ' + key + ' now exists in generated schema; remove the exception');
    continue;
  }
  const exception = exceptions.get(key);
  if (!exception || !exception.reason || exception.reviewRequired !== true) {
    failures.push('undocumented missing relationship: ' + key);
  } else {
    knownGaps.push(key);
  }
}
for (const key of exceptions.keys()) {
  if (!expected.some(([table,column,target,referencedColumn]) => [table,column,target,referencedColumn].join('|') === key)) {
    failures.push('exception is not part of the expected relationship matrix: ' + key);
  }
}
assert.deepEqual(failures, [], 'module relationship contract failed:\n' + failures.join('\n'));
console.log('Module relationship contract passed: ' + verified + ' relationships verified across ' + tables.size + ' generated table types; ' + knownGaps.length + ' known FK gaps are explicitly registered for forward-only remediation.');
