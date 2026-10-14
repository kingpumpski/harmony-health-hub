import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20261014110000_diagnostic_workflow_settings_and_context.sql');
const labSchema = read('supabase/migrations/20261013180000_laboratory_test_panels.sql');
const labQueue = read('supabase/migrations/20261013170000_lab_paid_queue_reports_and_catalogue.sql');
const imaging = read('src/pages/Imaging.tsx');
const laboratory = read('src/pages/Laboratory.tsx');
const header = read('src/components/layout/Header.tsx');
const styles = read('src/index.css');
const app = read('src/App.tsx');

function assert(name, condition) {
  if (!condition) throw new Error(`Diagnostic workflow integrity contract failed: ${name}`);
}

assert('settings extend the canonical facility settings table without creating a duplicate', 
  migration.includes('ALTER TABLE public.facility_settings') &&
  migration.includes('allow_lab_ordering boolean NOT NULL DEFAULT false') &&
  migration.includes('allow_radiology_ordering boolean NOT NULL DEFAULT false') &&
  migration.includes('REFERENCES public.healthcare_facilities(id)'));
assert('workflow settings read requires authentication and facility context',
  migration.includes('CREATE OR REPLACE FUNCTION public.get_facility_workflow_settings()') &&
  migration.includes('Select an active facility to access the imaging workspace') &&
  migration.includes('REVOKE ALL ON FUNCTION public.get_facility_workflow_settings() FROM PUBLIC, anon'));
assert('workflow setting writes are admin-only and preserve existing notification settings',
  migration.includes('CREATE OR REPLACE FUNCTION public.set_facility_workflow_settings') &&
  migration.includes("public.has_role(uid, 'admin')") &&
  migration.includes('coalesce(_notification_settings, facility_settings.notification_settings)'));
const imagingWorkspace = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.get_imaging_workspace'),
  migration.indexOf('REVOKE ALL ON FUNCTION public.get_imaging_workspace')
);
assert('imaging worklist is facility-scoped and includes unpaid and cancelled rows',
  imagingWorkspace.includes('WHERE io.facility_id = facility') &&
  imagingWorkspace.includes('p.facility_id = facility') &&
  imagingWorkspace.includes('AS billing_status') &&
  !imagingWorkspace.includes("WHERE io.status IN ('released', 'in_progress', 'completed')"));
assert('clinical context RPC validates order, patient and encounter facility lineage',
  migration.includes('CREATE OR REPLACE FUNCTION public.get_diagnostic_order_clinical_context') &&
  migration.includes('order_facility IS DISTINCT FROM facility') &&
  migration.includes('encounter_row.patient_id IS DISTINCT FROM order_patient') &&
  migration.includes('encounter_row.facility_id IS DISTINCT FROM order_facility') &&
  migration.includes('REVOKE ALL ON FUNCTION public.get_diagnostic_order_clinical_context(uuid, text) FROM PUBLIC, anon'));
assert('department-originated order inserts respect facility switches',
  migration.includes('CREATE OR REPLACE FUNCTION public.enforce_diagnostic_ordering_configuration') &&
  migration.includes('Radiology ordering is disabled for this facility') &&
  migration.includes('Laboratory ordering is disabled for this facility'));
assert('critical lab notifications are facility-member and clinical-role scoped',
  migration.includes('CREATE OR REPLACE FUNCTION public.notify_critical_lab_result') &&
  migration.includes('public.facility_memberships') &&
  migration.includes('fm.facility_id = NEW.facility_id') &&
  migration.includes("'critical_lab_result'"));
assert('radiology result and paid diagnostic invoice notifications are installed',
  migration.includes('CREATE OR REPLACE FUNCTION public.notify_imaging_result_ready') &&
  migration.includes('CREATE OR REPLACE FUNCTION public.notify_paid_diagnostic_invoice') &&
  migration.includes("'diagnostic_invoice_paid'"));
assert('existing operational audit pipeline covers diagnostic attachments and panels',
  migration.includes("'lab_result_attachments'") &&
  migration.includes("'lab_test_groups'") &&
  migration.includes("'lab_test_group_items'") &&
  migration.includes('public.audit_operational_row_change()'));
assert('notifications Realtime publication is added idempotently',
  migration.includes('pg_publication_tables') &&
  migration.includes('ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications'));
assert('lab panel migration references the canonical facility table',
  labSchema.includes('REFERENCES public.healthcare_facilities(id)') &&
  !labSchema.includes('REFERENCES public.facilities(id)'));
const laboratoryWorkspace = labSchema.slice(
  labSchema.indexOf('CREATE OR REPLACE FUNCTION public.get_laboratory_workspace'),
  labSchema.indexOf('REVOKE ALL ON FUNCTION public.get_laboratory_workspace')
);
assert('laboratory queue retains unpaid panel and individual orders for display',
  laboratoryWorkspace.includes('LEFT JOIN LATERAL') &&
  laboratoryWorkspace.includes('so.status AS billing_status') &&
  laboratoryWorkspace.includes('coalesce(lo.parent_order_id,lo.id)') &&
  !laboratoryWorkspace.includes("AND s.status IN ('released','in_progress','completed')") &&
  labQueue.includes('so.status AS billing_status'));
assert('imaging ordering form is disabled by default and only appears in a modal when enabled',
  imaging.includes("useState(false)") &&
  imaging.includes("allowRadiologyOrdering && <div") &&
  imaging.includes('setCreateModalOpen(true)') &&
  imaging.includes('role=\'dialog\' aria-modal=\'true\''));
assert('imaging worklist combines completed and active orders and locks unpaid actions',
  imaging.includes("title='Radiology worklist'") &&
  !imaging.includes("title='Completed order list'") &&
  imaging.includes("Awaiting payment") &&
  imaging.includes("order.status === 'released' && ['released', 'in_progress', 'completed'].includes(order.billing_status ?? '')"));
assert('imaging and laboratory worklists offer scoped read-only clinical context',
  imaging.includes("_order_type: 'imaging'") &&
  laboratory.includes("_order_type: 'laboratory'") &&
  imaging.includes('chief_complaint') &&
  laboratory.includes('chief_complaint'));
assert('laboratory unpaid orders cannot enter result or approval workflows',
  laboratory.includes("status={!isLabOrderPaid(o) && o.status !== 'cancelled' ? 'awaiting_payment' : o.status}") &&
  laboratory.includes('Awaiting payment — actions locked') &&
  laboratory.includes('resultFor === o.id && o.status === \'sample_collected\' && isLabOrderPaid(o)'));
assert('laboratory dashboard does not duplicate the global notification button',
  !laboratory.includes('> Notifications</Link>'));
assert('global header has realtime bell, finite shake, critical toast and deep link',
  header.includes('table: "notifications"') &&
  header.includes('setBellShaking(true)') &&
  header.includes('criticalToast.link') &&
  header.includes('role="alert"') &&
  styles.includes('notification-bell-vibrate 0.45s ease-in-out 7') &&
  styles.includes('notification-bell-pulse-reduced 1.5s ease-in-out 2'));
assert('the application already has a global error boundary and diagnostic routes',
  app.includes('class AppErrorBoundary') &&
  app.includes('path="/laboratory"') &&
  app.includes('path="/radiology"'));

console.log('Diagnostic workflow integrity contract passed.');
