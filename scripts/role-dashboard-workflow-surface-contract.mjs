import fs from 'node:fs';
import assert from 'node:assert/strict';

const workflow = fs.readFileSync('src/components/WorkflowSummary.tsx','utf8');
const dashboard = fs.readFileSync('src/pages/Dashboard.tsx','utf8');
const handoff = fs.readFileSync('src/components/workflow/OperationalHandoffPanel.tsx','utf8');
const kpi = fs.readFileSync('supabase/migrations/20260929170000_role_dashboard_workflow_kpi_alignment.sql','utf8');
const kpiCleanup = fs.readFileSync('supabase/migrations/20260929200000_role_dashboard_kpi_cleanup.sql','utf8');

assert.match(workflow,/Role-specific operational shortcuts/);
assert.match(workflow,/className="mt-8 border-t border-border pt-6"/);
assert.match(workflow,/if \(role === 'canteen'\)/);
assert.match(workflow,/if \(role === 'patient'\)/);
assert.match(workflow,/if \(role === 'radiology_technician'\)/);
assert.doesNotMatch(workflow,/Awaiting Accounts/);
assert.doesNotMatch(workflow,/Radiology results.*radiology_technician/);
assert.doesNotMatch(workflow,/Payment release/);
assert.doesNotMatch(workflow,/Laboratory work.*radiology_technician/);
assert.doesNotMatch(dashboard,/WorkflowSummary/);
assert.match(dashboard,/showReferral/);
assert.match(dashboard,/showSettlement/);
assert.match(dashboard,/OperationalHandoffPanel/);
assert.match(handoff,/get_workflow_notifications/);
assert.match(handoff,/Shared workflow communication/);
assert.match(handoff,/Open communication center/);
assert.match(handoff,/roleLabels/);
for (const role of ['admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist','accountant','front_desk','canteen','patient','it_admin']) {
  assert.match(handoff, new RegExp(role));
}
assert.doesNotMatch(handoff,/from\(['"]notifications['"]\)/);
assert.doesNotMatch(handoff,/select\(['"]\*['"]\)/);
assert.doesNotMatch(handoff,/postgres_changes/);
assert.match(kpi,/v_role = 'radiologist'/);
assert.match(kpi,/v_role = 'radiology_technician'/);
assert.match(kpi,/Ready for interpretation/);
const radiologistStart = kpi.indexOf("ELSIF v_role = 'radiologist'");
const radiologyTechnicianStart = kpi.indexOf("ELSIF v_role = 'radiology_technician'");
const radiologistBlock = radiologistStart >= 0 && radiologyTechnicianStart > radiologistStart ? kpi.slice(radiologistStart, radiologyTechnicianStart) : '';
assert.ok(radiologistBlock.length > 0);
assert.doesNotMatch(radiologistBlock,/'key','progress'/);
assert.match(kpi,/Ready for acquisition/);
assert.doesNotMatch(kpi,/v_role IN \('radiologist','radiology_technician'\)/);
assert.doesNotMatch(kpi,/Awaiting release/);
assert.doesNotMatch(kpi,/Ready for imaging/);

console.log('Role dashboard workflow surface contract: shared communication and role boundaries passed');
assert.doesNotMatch(kpiCleanup,/medication administration/i);
assert.doesNotMatch(workflow,/make\('Specialist referrals'.*admin/);
