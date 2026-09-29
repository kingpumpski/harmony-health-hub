import fs from 'node:fs';
import assert from 'node:assert/strict';

const kpi = fs.readFileSync('supabase/migrations/20260929193000_role_dashboard_kpi_semantic_alignment.sql','utf8');

const radiologistBlock = kpi.match(/ELSIF v_role='radiologist'[\\s\\S]*?ELSIF v_role='radiology_technician'/)?.[0] ?? '';
assert.ok(radiologistBlock.length > 0);
assert.match(radiologistBlock,/Ready for interpretation/);
assert.match(radiologistBlock,/Urgent \/ STAT/);
assert.doesNotMatch(radiologistBlock,/status IN \\('released','queued','in_progress'\\)/);

const technicianBlock = kpi.match(/ELSIF v_role='radiology_technician'[\\s\\S]*?ELSIF v_role='pharmacist'/)?.[0] ?? '';
assert.ok(technicianBlock.length > 0);
assert.match(technicianBlock,/Ready for acquisition/);
assert.match(technicianBlock,/Acquisition in progress/);
assert.match(technicianBlock,/status IN \\('released','queued','in_progress'\\)/);

const pharmacistBlock = kpi.match(/ELSIF v_role='pharmacist'[\\s\\S]*?ELSIF v_role='accountant'/)?.[0] ?? '';
assert.ok(pharmacistBlock.length > 0);
assert.match(pharmacistBlock,/Dispensing queue/);
assert.match(pharmacistBlock,/Expiry watch/);
assert.doesNotMatch(pharmacistBlock,/Medication administration/);

console.log('Role dashboard KPI semantic contract: 10 assertions passed');
