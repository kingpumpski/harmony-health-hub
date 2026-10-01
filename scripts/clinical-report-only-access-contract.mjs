import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const migrationPath = 'supabase/migrations/20261001150400_clinician_report_only_access.sql';
const migration = read(migrationPath);
const app = read('src/App.tsx');
const sidebar = read('src/components/layout/Sidebar.tsx');
const permissions = read('src/lib/permissions.ts');
const labResultsPage = read('src/pages/LaboratoryResults.tsx');
const radiologyResultsPage = read('src/pages/ClinicalResults.tsx');
const workflowSummary = read('src/components/WorkflowSummary.tsx');

function assert(name, condition) {
  if (!condition) throw new Error(`Clinical report access contract failed: ${name}`);
}

const labWorkspace = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.get_laboratory_workspace'),
  migration.indexOf('REVOKE ALL ON FUNCTION public.get_laboratory_workspace')
);
const imagingWorkspace = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.get_imaging_workspace'),
  migration.indexOf('REVOKE ALL ON FUNCTION public.get_imaging_workspace')
);
const labReportRpc = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.get_clinician_lab_results'),
  migration.indexOf('REVOKE ALL ON FUNCTION public.get_clinician_lab_results')
);
const imagingReportRpc = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.get_clinician_imaging_results'),
  migration.indexOf('REVOKE ALL ON FUNCTION public.get_clinician_imaging_results')
);

assert('laboratory operational workspace is restricted to administrators and lab technicians',
  labWorkspace.includes("public.has_role(auth.uid(), 'admin')") &&
  labWorkspace.includes("public.has_role(auth.uid(), 'lab_technician')") &&
  !/public\.has_role\(auth\.uid\(\), '(?:practitioner|nurse|midwife|specialist_nurse|radiologist)'\)/.test(labWorkspace));
assert('imaging operational workspace is restricted to imaging staff and administrators',
  imagingWorkspace.includes("public.has_role(auth.uid(), 'admin')") &&
  imagingWorkspace.includes("public.has_role(auth.uid(), 'radiologist')") &&
  imagingWorkspace.includes("public.has_role(auth.uid(), 'radiology_technician')") &&
  !imagingWorkspace.includes("public.has_role(auth.uid(), 'practitioner')"));
assert('clinician lab report RPC returns approved results only',
  labReportRpc.includes("r.status = 'approved'") &&
  labReportRpc.includes("o.status = 'approved'") &&
  labReportRpc.includes('public.current_user_has_facility_access') &&
  labReportRpc.includes('o.ordered_by = uid OR e.practitioner_id = uid'));
assert('clinician imaging report RPC returns completed reports only',
  imagingReportRpc.includes("io.status = 'completed'") &&
  imagingReportRpc.includes('public.current_user_has_facility_access') &&
  imagingReportRpc.includes('io.requested_by = uid OR e.practitioner_id = uid'));
assert('report RPCs are not executable by anonymous callers',
  migration.includes('REVOKE ALL ON FUNCTION public.get_clinician_lab_results(integer) FROM PUBLIC, anon') &&
  migration.includes('REVOKE ALL ON FUNCTION public.get_clinician_imaging_results(integer) FROM PUBLIC, anon'));
assert('laboratory results route renders the report-only page',
  app.includes('<Route path="/lab-results" element={<RoleGuard allowedRoles={resultReviewRoles}><LaboratoryResults /></RoleGuard>} />') &&
  app.includes("const LaboratoryResults = lazy(() => import('./pages/LaboratoryResults'))"));
assert('diagnostic department routes remain role-restricted',
  app.includes('<Route path="/laboratory" element={<RoleGuard allowedRoles={laboratoryWorkspaceRoles}><Laboratory /></RoleGuard>} />') &&
  app.includes('<Route path="/radiology" element={<RoleGuard allowedRoles={radiologyWorkspaceRoles}><Imaging /></RoleGuard>} />'));
assert('clinician navigation exposes report links but not diagnostic workspaces',
  sidebar.slice(sidebar.indexOf('  practitioner:'), sidebar.indexOf('  nurse:')).includes("'/lab-results'") &&
  sidebar.slice(sidebar.indexOf('  practitioner:'), sidebar.indexOf('  nurse:')).includes("'/clinical-results'") &&
  !sidebar.slice(sidebar.indexOf('  practitioner:'), sidebar.indexOf('  nurse:')).includes("'/laboratory'") &&
  !sidebar.slice(sidebar.indexOf('  practitioner:'), sidebar.indexOf('  nurse:')).includes("'/radiology'"));
assert('clinical defaults do not grant practitioner diagnostic workspace permissions',
  !permissions.slice(permissions.indexOf('  practitioner:'), permissions.indexOf('  nurse:')).includes("'laboratory'") &&
  !permissions.slice(permissions.indexOf('  practitioner:'), permissions.indexOf('  nurse:')).includes("'radiology'") &&
  !permissions.slice(permissions.indexOf('  practitioner:'), permissions.indexOf('  nurse:')).includes("'pharmacy'"));
assert('clinician laboratory report page is read-only',
  labResultsPage.includes("rpc('get_clinician_lab_results'") &&
  !labResultsPage.includes("rpc('approve_lab_result'") &&
  !labResultsPage.includes("rpc('enter_lab_result") &&
  !labResultsPage.includes("rpc('collect_lab_sample'"));
assert('radiology report page uses the scoped report RPC',
  radiologyResultsPage.includes("rpc('get_clinician_imaging_results'") &&
  !radiologyResultsPage.includes(".from('imaging_orders')"));
assert('practitioner dashboard shortcuts do not link to diagnostic workspaces',
  workflowSummary.slice(workflowSummary.indexOf("if (role === 'practitioner')"), workflowSummary.indexOf("if (role === 'nurse'"))
    .includes("make('Laboratory results','/lab-results'") &&
  workflowSummary.slice(workflowSummary.indexOf("if (role === 'practitioner')"), workflowSummary.indexOf("if (role === 'nurse'"))
    .includes("make('Radiology results','/clinical-results'") &&
  !workflowSummary.slice(workflowSummary.indexOf("if (role === 'practitioner')"), workflowSummary.indexOf("if (role === 'nurse'"))
    .includes("'/laboratory'") &&
  !workflowSummary.slice(workflowSummary.indexOf("if (role === 'practitioner')"), workflowSummary.indexOf("if (role === 'nurse'"))
    .includes("'/radiology'"));

console.log('Clinical report-only access contract passed');
