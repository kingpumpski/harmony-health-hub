import fs from 'node:fs';
import assert from 'node:assert/strict';

const workflow = fs.readFileSync('src/components/WorkflowSummary.tsx','utf8');
const dashboard = fs.readFileSync('src/pages/Dashboard.tsx','utf8');
const kpi = fs.readFileSync('supabase/migrations/20260929170000_role_dashboard_workflow_kpi_alignment.sql','utf8');

assert.match(workflow,/Role-specific operational shortcuts/);
assert.match(workflow,/className="mt-8 border-t border-border pt-6"/);
assert.match(workflow,/if \(role === 'canteen'\)/);
assert.match(workflow,/make\('Meal menu','\/menu'/);
assert.match(workflow,/if \(role === 'patient'\)/);
assert.match(workflow,/make\('Meal menu','\/menu'/);
assert.match(workflow,/if \(role === 'radiology_technician'\)/);
assert.doesNotMatch(workflow,/Awaiting Accounts/);
assert.doesNotMatch(workflow,/Radiology results.*radiology_technician/);
assert.doesNotMatch(workflow,/Payment release/);
assert.doesNotMatch(workflow,/Laboratory work.*radiology_technician/);
assert.match(dashboard,/\{dashboard\}\s*<WorkflowSummary\/>/);
assert.doesNotMatch(dashboard,/\{\s*<WorkflowSummary\/>\s*\}\s*\{showReferral/);
assert.match(kpi,/v_role = 'radiologist'/);
assert.match(kpi,/v_role = 'radiology_technician'/);
assert.match(kpi,/Ready for interpretation/);
const radiologistBlock = kpi.match(/ELSIF v_role = 'radiologist'[\\s\\S]*?ELSIF v_role = 'radiology_technician'/)?.[0] ?? '';
assert.ok(radiologistBlock.length > 0);
assert.doesNotMatch(radiologistBlock,/'key','progress'/);
assert.match(kpi,/Ready for acquisition/);
assert.doesNotMatch(kpi,/v_role IN \('radiologist','radiology_technician'\)/);
assert.doesNotMatch(kpi,/Awaiting release/);
assert.doesNotMatch(kpi,/Ready for imaging/);

console.log('Role dashboard workflow surface contract: 16 assertions passed');
assert.doesNotMatch(kpi,/v_role = 'pharmacist'[\\s\\S]*'key','medications'/);
assert.doesNotMatch(workflow,/make\('Specialist referrals'.*admin/);
