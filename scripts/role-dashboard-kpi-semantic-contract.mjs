import fs from 'node:fs';
import assert from 'node:assert/strict';

const kpi = fs.readFileSync('supabase/migrations/20260929193000_role_dashboard_kpi_semantic_alignment.sql','utf8');

assert.match(kpi,/v_role='radiologist'/);
assert.match(kpi,/Ready for interpretation/);
assert.match(kpi,/Urgent \/ STAT/);
assert.doesNotMatch(kpi,/v_role='radiologist'[\\s\\S]*status IN \\('released','queued','in_progress'\\)/);

assert.match(kpi,/v_role='radiology_technician'/);
assert.match(kpi,/Ready for acquisition/);
assert.match(kpi,/Acquisition in progress/);
assert.match(kpi,/status IN \\('released','queued','in_progress'\\)/);

assert.match(kpi,/v_role='pharmacist'/);
assert.match(kpi,/Dispensing queue/);
assert.match(kpi,/Expiry watch/);
assert.doesNotMatch(kpi,/Medication administration/);

console.log('Role dashboard KPI semantic contract: 10 assertions passed');
