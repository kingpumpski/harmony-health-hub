import assert from 'node:assert/strict';
import {
  clinicalMigrationSourceFormat,
  parseClinicalMigrationText,
} from '../src/lib/clinicalMigrationFormats.mjs';

const bundle = {
  resourceType: 'Bundle',
  type: 'collection',
  entry: [
    { resource: { resourceType: 'Patient', id: 'pat-01', name: [{ text: 'Ama Mensah' }] } },
    {
      resource: {
        resourceType: 'Observation',
        id: 'obs-01',
        subject: { reference: 'Patient/pat-01' },
        effectiveDateTime: '2026-10-20T10:30:00Z',
        code: { text: 'Blood pressure' },
        valueString: '120/80 mmHg',
      },
    },
  ],
};
const fhirRows = parseClinicalMigrationText('records.json', JSON.stringify(bundle), 'Legacy HIS');
assert.equal(fhirRows.length, 2);
assert.equal(fhirRows[0].source_patient_key, 'pat-01');
assert.equal(fhirRows[1].source_patient_key, 'pat-01');
assert.equal(fhirRows[1].record_type, 'Observation');
assert.equal(fhirRows[1].occurred_at, '2026-10-20T10:30:00.000Z');
assert.equal(fhirRows[1].raw_record.id, 'obs-01');
assert.equal(fhirRows[1].source_system, 'Legacy HIS');

const genericRows = parseClinicalMigrationText('records.json', JSON.stringify({
  records: [{ patient_id: 'P-3', record_type: 'allergy', summary: 'Penicillin allergy', date: '2025-04-01' }],
}));
assert.equal(genericRows[0].source_patient_key, 'P-3');
assert.equal(genericRows[0].clinical_summary, 'Penicillin allergy');
assert.equal(genericRows[0].occurred_at, '2025-04-01T00:00:00.000Z');

const hl7 = [
  'MSH|^~\\&|LEGACY|FACILITY|HARMONY|FACILITY|20261028103000||ORU^R01|MSG-7|P|2.5',
  'PID|1||PAT-42^^^HOSP^MR||Mensah^Ama',
  'PV1|1|O|||||||||||||||||ENC-8',
  'OBX|1|ST|BP^Blood Pressure||120/80 mmHg||||||F|||20261028103000',
].join('\r');
const hl7Rows = parseClinicalMigrationText('sample.hl7', hl7, 'Legacy HIS');
assert.ok(hl7Rows.length >= 2);
assert.ok(hl7Rows.every((row) => row.source_patient_key === 'PAT-42'));
assert.ok(hl7Rows.some((row) => row.record_type === 'OBX' && row.clinical_summary === '120/80 mmHg'));
assert.equal(clinicalMigrationSourceFormat('sample.hl7'), 'hl7');
assert.equal(clinicalMigrationSourceFormat('sample.xml'), 'xml');
assert.equal(clinicalMigrationSourceFormat('bundle.json'), 'json');

const xmlNode = (name, text = '', children = []) => {
  const element = {
    localName: name,
    nodeName: name,
    attributes: [],
    children,
    textContent: text || children.map((child) => child.textContent).join(''),
    getElementsByTagName: () => [],
  };
  for (const child of children) child.parentElement = element;
  return element;
};
const xmlRecord = xmlNode('record', '', [
  xmlNode('id', 'xml-01'),
  xmlNode('patient_id', 'PAT-XML'),
  xmlNode('record_type', 'Condition'),
  xmlNode('summary', 'Asthma history'),
  xmlNode('date', '2024-11-05'),
]);
const xmlRoot = xmlNode('records', '', [xmlRecord]);
globalThis.DOMParser = class {
  parseFromString() {
    return { documentElement: xmlRoot, querySelector: () => null };
  }
};
const xmlRows = parseClinicalMigrationText('records.xml', '<records />', 'XML Legacy');
assert.equal(xmlRows[0].source_patient_key, 'PAT-XML');
assert.equal(xmlRows[0].record_type, 'Condition');
assert.equal(xmlRows[0].clinical_summary, 'Asthma history');
assert.throws(() => parseClinicalMigrationText('unsafe.xml', '<!DOCTYPE x [<!ENTITY y "z">]><x>&y;</x>'), /DTD and entity declarations/);
delete globalThis.DOMParser;

assert.throws(() => parseClinicalMigrationText('bad.json', '{not-json'), /JSON is malformed/);
assert.throws(() => parseClinicalMigrationText('wrong.txt', 'anything'), /Choose JSON\/FHIR Bundle/);
assert.throws(() => parseClinicalMigrationText('empty.json', '  '), /file is empty/);

console.log('Clinical migration format regression checks passed.');
