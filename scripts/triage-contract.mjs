import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const presentation = readFileSync(new URL('../src/lib/triagePresentation.ts', import.meta.url), 'utf8');
const chart = readFileSync(new URL('../src/components/triage/TriageHistoryChart.tsx', import.meta.url), 'utf8');
const form = readFileSync(new URL('../src/components/triage/TriageRecordForm.tsx', import.meta.url), 'utf8');
const hub = readFileSync(new URL('../src/pages/patients/PatientHub.tsx', import.meta.url), 'utf8');
const page = readFileSync(new URL('../src/pages/Triage.tsx', import.meta.url), 'utf8');

assert.match(presentation, /patientId\?\.trim\(\)/, 'blank patient IDs must normalize to null');
assert.match(presentation, /return records;\n  return records\.filter/, 'parameter filtering must operate on the already loaded dataset');
assert.match(presentation, /temp: 0\.5/, 'temperature interval must be 0.5');
assert.match(presentation, /bp: 10/, 'blood-pressure interval must be 10');
assert.match(presentation, /bmi: 2/, 'BMI interval must be 2');
assert.match(presentation, /spo2: 2/, 'SpO2 interval must be 2');

assert.match(hub, /get_patient_triage_history/, 'Patient Hub must use the scoped triage RPC');
assert.match(hub, /_patient_id: scopedPatientId/, 'Patient Hub must send the selected patient ID to the data layer');
assert.match(hub, /No triage records yet for this patient/, 'Patient Hub must expose a patient-scoped empty state');
assert.match(hub, /Unable to load triage history\. Retry\./, 'Patient Hub must expose a retryable error state');
assert.match(hub, /aria-label="Loading triage history"/, 'Patient Hub must expose a loading state');
assert.match(hub, /\['all', 'temp', 'bp', 'bmi', 'spo2'\]/, 'Patient Hub must expose All + required parameter filters');
assert.match(hub, /<nav aria-label="Triage parameter filters" className="mt-2 border-t pt-3">/, 'triage filters must sit directly beneath the graph as a dedicated legend row');
assert.match(hub, /Select a parameter to isolate its trend; the markers match the plotted series\./, 'triage filter labels must explain that their visual markers match the graph series');
assert.match(hub, /bg-\[hsl\(var\(--warning\)\)\]/, 'temperature filter must use the graph temperature color');
assert.match(hub, /bg-\[hsl\(var\(--destructive\)\)\]/, 'BP systolic filter marker must use the graph systolic color');
assert.match(hub, /bg-\[hsl\(var\(--success\)\)\]/, 'BMI filter must use the graph BMI color');
assert.match(hub, /bg-\[hsl\(var\(--info\)\)\]/, 'SpO2 filter must use the graph SpO2 color');

assert.match(chart, /dataKey="systolic"/, 'BP must render systolic');
assert.match(chart, /dataKey="diastolic"/, 'BP must render diastolic');
assert.match(chart, /stackId="bpBand"/, 'BP must render a band between systolic and diastolic');
assert.match(chart, /ReferenceArea yAxisId="bmi"/, 'BMI must render reference zones');
assert.match(chart, /ReferenceArea yAxisId="spo2"/, 'SpO2 must render a clinical threshold zone');
assert.match(chart, /minTickGap=\{28\}/, 'time-axis labels must avoid overlap');

assert.match(form, /input\('systolic', 'Systolic BP', '90–120 mmHg · e\.g\. 120'/, 'SBP field must guide data entry');
assert.match(form, /input\('diastolic', 'Diastolic BP', '60–80 mmHg · e\.g\. 80'/, 'DBP field must guide data entry');
assert.match(form, /input\('temperature', 'Temperature °C', '36\.1–37\.2 °C · e\.g\. 36\.8'/, 'temperature field must guide data entry');
assert.match(form, /input\('oxygenSaturation', 'SpO₂ %', '95–100% · e\.g\. 98'/, 'SpO2 field must guide data entry');
assert.match(form, /Enter at least one measured vital sign\./, 'partial-measurement validation must be explicit');
assert.match(form, /function numberOrNull\(value: string\) \{\n  return value\.trim\(\) === '' \? null : Number\(value\);\n\}/, 'empty numeric inputs must normalize to null');
assert.doesNotMatch(form, /_systolic:\s*Number\(form\.systolic\)/, 'SBP payload must not coerce an empty field to zero');
assert.doesNotMatch(form, /_diastolic:\s*Number\(form\.diastolic\)/, 'DBP payload must not coerce an empty field to zero');
assert.doesNotMatch(form, /_heart_rate:\s*Number\(form\.heartRate\)/, 'heart-rate payload must not coerce an empty field to zero');
assert.doesNotMatch(form, /_temperature:\s*Number\(form\.temperature\)/, 'temperature payload must not coerce an empty field to zero');
assert.doesNotMatch(form, /_respiratory_rate:\s*Number\(form\.respiratoryRate\)/, 'respiratory-rate payload must not coerce an empty field to zero');
assert.doesNotMatch(form, /_oxygen_saturation:\s*Number\(form\.oxygenSaturation\)/, 'SpO2 payload must not coerce an empty field to zero');

assert.match(page, /Add Record/, 'Triage landing view must expose Add Record');
assert.match(page, /TriageRecordForm/, 'Triage landing view must use the guided form');
assert.match(page, /No triage records yet/, 'Triage landing view must expose an empty state');

console.log('Triage contract tests passed: scoping, filters, BP dual-line/band, intervals, states, list/add flow, entry placeholders, and nullable measurements.');
