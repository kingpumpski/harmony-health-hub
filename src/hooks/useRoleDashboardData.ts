import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type DashboardRole = 'practitioner' | 'lab_technician' | 'pharmacist' | 'accountant' | 'nurse';
export type DashboardMetric = { label: string; value: string | number; href?: string; description?: string; trend?: string };
export type DashboardActivity = { id: string; title: string; detail?: string; createdAt?: string; href?: string };
export type DashboardAlert = { id: string; title: string; detail?: string; href?: string; severity?: 'critical' | 'warning' | 'info' };
export type RoleDashboardData = {
  topMetrics: DashboardMetric[];
  secondaryMetrics: DashboardMetric[];
  activities: DashboardActivity[];
  upcoming: DashboardActivity[];
  alerts: DashboardAlert[];
};

type Row = {
  id: string;
  created_at?: string;
  updated_at?: string;
  scheduled_at?: string;
  status?: string;
  priority?: string | null;
  test_name?: string;
  medication?: string;
  study_name?: string;
  report?: string | null;
  is_abnormal?: boolean | null;
  severity?: string;
  acknowledged_at?: string | null;
  expiry_date?: string | null;
  stock_quantity?: number;
  reorder_level?: number | null;
  total_amount?: number;
  paid_amount?: number;
  outstanding_amount?: number | null;
  invoice_number?: string;
  first_name?: string | null;
  last_name?: string | null;
  patients?: { first_name?: string | null; last_name?: string | null } | null;
};

const patientName = (row: Row) => {
  const person = row.patients;
  const name = [person?.first_name ?? row.first_name, person?.last_name ?? row.last_name].filter(Boolean).join(' ');
  return name || 'Patient';
};

const makeActivity = (row: Row, title: string, detail?: string, href?: string): DashboardActivity => ({
  id: row.id,
  title,
  detail,
  createdAt: row.created_at ?? row.scheduled_at,
  href,
});

const ensure = <T,>(result: { data: T | null; error: { message: string } | null }, label: string): T => {
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  return result.data as T;
};

async function fetchClinician(userId?: string): Promise<RoleDashboardData> {
  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  const dayEnd = new Date();
  dayEnd.setHours(23, 59, 59, 999);
  const now = new Date();
  const nextWeek = new Date(now.getTime() + 7 * 86400000);
  const monthStart = new Date(dayStart.getFullYear(), dayStart.getMonth(), 1).toISOString();
  const [appointmentsResult, upcomingResult, labResult, imagingResult, serviceOrdersResult, workflowNotificationsResult, admissionsResult, encounterResult, abnormalResult, monthlyEncounterResult, totalEncounterResult] = await Promise.all([
    supabase.from('appointments').select('id,scheduled_at,status,reason,patients(first_name,last_name)', { count: 'exact' }).eq('practitioner_id', userId ?? '').in('status', ['scheduled', 'checked_in']).gte('scheduled_at', dayStart.toISOString()).lte('scheduled_at', dayEnd.toISOString()).order('scheduled_at').limit(100),
    supabase.from('appointments').select('id,scheduled_at,status,reason,patients(first_name,last_name)').eq('practitioner_id', userId ?? '').in('status', ['scheduled', 'checked_in']).gte('scheduled_at', now.toISOString()).lte('scheduled_at', nextWeek.toISOString()).order('scheduled_at').limit(3),
    supabase.from('lab_orders').select('id,test_name,status,created_at,patients(first_name,last_name)').eq('status', 'completed').order('created_at', { ascending: false }).limit(30),
    supabase.from('imaging_orders').select('id,study_name,status,report,created_at,patients(first_name,last_name)').eq('status', 'completed').is('report', null).order('created_at', { ascending: false }).limit(30),
    supabase.from('service_orders').select('id,status,created_at').order('created_at', { ascending: false }).limit(500),
    supabase.rpc('get_workflow_notifications', { _limit: 100 }),
    supabase.from('admissions').select('id', { count: 'exact', head: true }).eq('status', 'admitted'),
    supabase.from('encounters').select('id,status,created_at,completed_at,patients(first_name,last_name),patient_id').eq('practitioner_id', userId ?? '').gte('created_at', monthStart).order('created_at', { ascending: false }).limit(500),
    supabase.from('lab_results').select('id,is_abnormal,created_at,lab_orders(test_name,patients(first_name,last_name))').eq('is_abnormal', true).order('created_at', { ascending: false }).limit(10),
    supabase.from('encounters').select('id', { count: 'exact', head: true }).eq('practitioner_id', userId ?? '').gte('created_at', monthStart).eq('status', 'completed'),
    supabase.from('encounters').select('id', { count: 'exact', head: true }).eq('practitioner_id', userId ?? '').gte('created_at', monthStart),
  ]);
  const appointments = ensure(appointmentsResult, 'Appointments unavailable') as unknown as Row[];
  const labs = ensure(labResult, 'Lab results unavailable') as unknown as Row[];
  const imaging = ensure(imagingResult, 'Radiology results unavailable') as unknown as Row[];
  const serviceOrders = ensure(serviceOrdersResult, 'Service orders unavailable') as unknown as Row[];
  const workflowNotifications = ensure(workflowNotificationsResult, 'Workflow notifications unavailable') as unknown as Array<{ id: string; title?: string; message?: string; severity?: string; is_read?: boolean; link?: string | null; created_at?: string }>;
  const pendingServiceOrders = serviceOrders.filter((row) => ['ordered', 'pending', 'in_progress', 'requested', 'scheduled'].includes(String(row.status ?? '').toLowerCase()));
  const urgentWorkflowNotifications = workflowNotifications.filter((row) => !row.is_read && ['critical', 'high', 'warning'].includes(String(row.severity ?? '').toLowerCase()));
  const encounters = ensure(encounterResult, 'Encounter metrics unavailable') as unknown as Row[];
  const abnormal = ensure(abnormalResult, 'Critical results unavailable') as unknown as Row[];
  const upcoming = ensure(upcomingResult, 'Upcoming appointments unavailable') as unknown as Row[];
  if (monthlyEncounterResult.error) throw new Error(`Monthly encounter count unavailable: ${monthlyEncounterResult.error.message}`);
  if (totalEncounterResult.error) throw new Error(`Monthly encounter total unavailable: ${totalEncounterResult.error.message}`);
  if (appointmentsResult.error) throw new Error(`Appointment count unavailable: ${appointmentsResult.error.message}`);
  if (serviceOrdersResult.error) throw new Error(`Service order queue unavailable: ${serviceOrdersResult.error.message}`);
  if (workflowNotificationsResult.error) throw new Error(`Workflow attention feed unavailable: ${workflowNotificationsResult.error.message}`);
  if (admissionsResult.error) throw new Error(`Inpatient count unavailable: ${admissionsResult.error.message}`);
  const patientsSeen = new Set(encounters.filter((row) => row.status === 'completed').map((row) => row.patient_id)).size;
  const completionRate = totalEncounterResult.count ? Math.round(((monthlyEncounterResult.count ?? 0) / totalEncounterResult.count) * 100) : null;
  return {
    topMetrics: [
      { label: "Today's Appointments", value: appointmentsResult.count ?? appointments.length, href: '/appointments' },
      { label: 'Pending Lab Results', value: labs.length, href: '/lab-results?status=pending' },
      { label: 'Pending Radiology', value: imaging.length, href: '/clinical-results' },
      { label: 'Pending Service Orders', value: pendingServiceOrders.length, href: '/encounters' },
      { label: 'Active Inpatients', value: admissionsResult.count ?? 0, href: '/inpatient' },
    ],
    secondaryMetrics: [
      { label: 'Total Patients Seen (This Month)', value: patientsSeen, href: '/patients' },
      { label: 'Encounters Completed', value: monthlyEncounterResult.count ?? 0, description: completionRate === null ? 'This month' : `${completionRate}% of encounters completed`, href: '/encounters' },
      { label: 'Average Consultation Time', value: '—', description: 'No consultation-duration records are available' },
    ],
    activities: [
      ...encounters.filter((row) => row.status === 'completed').slice(0, 3).map((row) => makeActivity(row, `Encounter completed for ${patientName(row)}`, 'Clinical encounter saved', '/encounters')),
      ...labs.slice(0, 3).map((row) => makeActivity(row, `Lab results ready for ${patientName(row)}`, row.test_name, '/lab-results?status=pending')),
      ...appointments.slice(0, 3).map((row) => makeActivity(row, `Appointment booked: ${patientName(row)}`, row.scheduled_at ? new Date(row.scheduled_at).toLocaleString() : '', '/appointments')),
    ].slice(0, 8),
    upcoming: upcoming.map((row) => makeActivity(row, patientName(row), row.scheduled_at ? new Date(row.scheduled_at).toLocaleString([], { weekday: 'short', hour: '2-digit', minute: '2-digit' }) : '', '/appointments')),
    alerts: [
      ...urgentWorkflowNotifications.slice(0, 5).map((row) => ({ id: row.id, title: row.title || 'Clinical attention required', detail: row.message || 'An unread workflow notification requires review.', createdAt: row.created_at, href: row.link || '/notifications', severity: String(row.severity).toLowerCase() === 'critical' ? 'critical' as const : 'warning' as const })),
      ...abnormal.slice(0, 5).map((row) => ({ ...makeActivity(row, 'Abnormal lab result', patientName(row), '/lab-results?status=pending'), severity: 'critical' as const })),
    ].slice(0, 8),
  };
}

async function fetchLaboratory(): Promise<RoleDashboardData> {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const monthStart = new Date(start.getFullYear(), start.getMonth(), 1).toISOString();
  const [pendingResult, inProcessResult, specimensResult, todayResult, monthlyResult, criticalResult, activityResult] = await Promise.all([
    supabase.from('lab_orders').select('id', { count: 'exact', head: true }).eq('status', 'ordered'),
    supabase.from('lab_orders').select('id', { count: 'exact', head: true }).in('status', ['sample_collected', 'in_progress']),
    supabase.rpc('get_laboratory_specimens', { _limit: 500 } as never),
    supabase.from('lab_orders').select('id', { count: 'exact', head: true }).eq('status', 'completed').gte('updated_at', start.toISOString()),
    supabase.from('lab_orders').select('id', { count: 'exact', head: true }).gte('created_at', monthStart),
    supabase.from('lab_results').select('id', { count: 'exact', head: true }).eq('is_abnormal', true).neq('status', 'approved'),
    supabase.from('lab_orders').select('id,test_name,status,created_at,patients(first_name,last_name)').order('created_at', { ascending: false }).limit(8),
  ]);
  for (const [result, name] of [[pendingResult, 'Pending sample count unavailable'], [inProcessResult, 'In-process test count unavailable'], [todayResult, 'Daily completions unavailable'], [monthlyResult, 'Monthly test count unavailable'], [criticalResult, 'Critical result count unavailable']] as const) {
    if (result.error) throw new Error(`${name}: ${result.error.message}`);
  }
  if (specimensResult.error) throw new Error(`Rejected sample count unavailable: ${specimensResult.error.message}`);
  const rejectedCount = Array.isArray(specimensResult.data)
    ? (specimensResult.data as Array<{ status?: string }>).filter((specimen) => specimen.status === 'rejected').length
    : 0;
  const activity = ensure(activityResult, 'Recent lab activity unavailable') as unknown as Row[];
  return {
    topMetrics: [
      { label: 'Pending Samples', value: pendingResult.count ?? 0, href: '/laboratory?status=ordered' },
      { label: 'In-Process Tests', value: inProcessResult.count ?? 0, href: '/laboratory?status=in_progress' },
      { label: 'Completed Today', value: todayResult.count ?? 0, href: '/laboratory?status=completed' },
      { label: 'Rejected Samples', value: rejectedCount, href: '/laboratory?status=rejected' },
    ],
    secondaryMetrics: [
      { label: 'Total Tests This Month', value: monthlyResult.count ?? 0, href: '/laboratory' },
      { label: 'Average Turnaround Time', value: '—', description: 'Not available from current turnaround records' },
      { label: 'Critical Results Flagged', value: criticalResult.count ?? 0, href: '/lab-results?status=pending' },
    ],
    activities: activity.map((row) => makeActivity(row, row.status === 'approved' ? `Result approved for ${patientName(row)}` : `Lab order ${row.status ?? 'updated'} for ${patientName(row)}`, row.test_name, '/laboratory')),
    upcoming: [],
    alerts: (criticalResult.count ?? 0) > 0 ? [{ id: 'critical-labs', title: 'Critical results require review', detail: `${criticalResult.count} abnormal result(s) are not yet approved.`, href: '/lab-results?status=pending', severity: 'critical' }] : [],
  };
}

async function fetchPharmacy(): Promise<RoleDashboardData> {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const monthStart = new Date(start.getFullYear(), start.getMonth(), 1).toISOString();
  const [prescriptionsResult, dispensedResult, inventoryResult, monthResult, salesResult] = await Promise.all([
    supabase.from('prescriptions').select('id,status', { count: 'exact', head: true }).eq('status', 'pending'),
    supabase.from('prescriptions').select('id,status', { count: 'exact', head: true }).eq('status', 'dispensed').gte('dispensed_at', start.toISOString()),
    supabase.from('pharmacy_inventory').select('id,drug_name,stock_quantity,reorder_level,expiry_date').order('drug_name').limit(300),
    supabase.from('prescriptions').select('id', { count: 'exact', head: true }).gte('created_at', monthStart),
    supabase.from('pharmacy_pos_sales').select('id,total_amount,dispensed_at,status').eq('status', 'dispensed').gte('dispensed_at', monthStart).limit(500),
  ]);
  if (prescriptionsResult.error) throw new Error(`Pending prescriptions unavailable: ${prescriptionsResult.error.message}`);
  if (dispensedResult.error) throw new Error(`Dispensing totals unavailable: ${dispensedResult.error.message}`);
  if (inventoryResult.error) throw new Error(`Pharmacy inventory unavailable: ${inventoryResult.error.message}`);
  if (monthResult.error) throw new Error(`Monthly prescription count unavailable: ${monthResult.error.message}`);
  if (salesResult.error) throw new Error(`Pharmacy revenue unavailable: ${salesResult.error.message}`);
  const inventory = (inventoryResult.data ?? []) as Row[];
  const sales = (salesResult.data ?? []) as Row[];
  const lowStock = inventory.filter((item) => item.stock_quantity <= (item.reorder_level ?? 0));
  const emptyStock = inventory.filter((item) => item.stock_quantity <= 0);
  const revenue = sales.reduce((total, sale) => total + (Number(sale.total_amount) || 0), 0);
  const activityResult = await supabase.from('prescriptions').select('id,medication,status,created_at,patients(first_name,last_name)').order('created_at', { ascending: false }).limit(6);
  const activity = ensure(activityResult, 'Recent pharmacy activity unavailable') as unknown as Row[];
  const expiring = inventory.filter((item) => item.expiry_date && Date.parse(item.expiry_date) >= Date.now() && Date.parse(item.expiry_date) <= Date.now() + 30 * 86400000);
  return {
    topMetrics: [
      { label: 'Pending Prescriptions', value: prescriptionsResult.count ?? 0, href: '/pharmacy' },
      { label: 'Dispensed Today', value: dispensedResult.count ?? 0, href: '/pharmacy' },
      { label: 'Out of Stock Items', value: emptyStock.length, href: '/inventory' },
      { label: 'Controlled Substances Alerts', value: '—', description: 'No controlled-substance alert feed is configured' },
    ],
    secondaryMetrics: [
      { label: 'Total Prescriptions (Month)', value: monthResult.count ?? 0, href: '/pharmacy' },
      { label: 'Average Dispense Time', value: '—', description: 'Not available from current dispensing records' },
      { label: 'Revenue from Pharmacy', value: `GHS ${revenue.toFixed(2)}`, href: '/financial-reports' },
    ],
    activities: activity.map((row) => makeActivity(row, `Prescription ${row.status ?? 'updated'} for ${patientName(row)}`, row.medication, '/pharmacy')),
    upcoming: [],
    alerts: [
      ...lowStock.slice(0, 5).map((item) => ({ id: item.id, title: `Low stock: ${item.drug_name}`, detail: `${item.stock_quantity} remaining (reorder at ${item.reorder_level ?? 0}).`, href: '/inventory', severity: 'warning' as const })),
      ...expiring.slice(0, 5).map((item) => ({ id: `expiry-${item.id}`, title: `Expiring soon: ${item.drug_name}`, detail: item.expiry_date ?? '', href: '/inventory', severity: 'warning' as const })),
    ],
  };
}

async function fetchAccounts(): Promise<RoleDashboardData> {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const monthStart = new Date(today.getFullYear(), today.getMonth(), 1).toISOString();
  const overdueSince = new Date(today.getTime() - 30 * 86400000).toISOString();
  const [invoiceResult, todayPaymentsResult, monthInvoicesResult, claimsResult, admissionsResult, overdueResult, recentResult] = await Promise.all([
    supabase.from('invoices').select('id,status,outstanding_amount,total_amount,paid_amount', { count: 'exact', head: true }).in('status', ['pending', 'partially_paid']),
    supabase.from('payments').select('id,amount,created_at').gte('created_at', today.toISOString()),
    supabase.from('invoices').select('id,total_amount,outstanding_amount,paid_amount', { count: 'exact' }).gte('created_at', monthStart).limit(500),
    supabase.from('insurance_claims').select('id,status', { count: 'exact', head: true }).ilike('provider', '%NHIS%').in('status', ['draft', 'submitted', 'acknowledged', 'under_review', 'resubmission_required']),
    supabase.from('admissions').select('id,status,created_at', { count: 'exact', head: true }).eq('status', 'admitted'),
    supabase.from('invoices').select('id', { count: 'exact', head: true }).in('status', ['pending', 'partially_paid']).lt('created_at', overdueSince),
    supabase.from('invoices').select('id,invoice_number,status,created_at,total_amount,patients(first_name,last_name)').order('created_at', { ascending: false }).limit(8),
  ]);
  if (invoiceResult.error) throw new Error(`Invoice totals unavailable: ${invoiceResult.error.message}`);
  if (todayPaymentsResult.error) throw new Error(`Today's collections unavailable: ${todayPaymentsResult.error.message}`);
  if (monthInvoicesResult.error) throw new Error(`Monthly revenue unavailable: ${monthInvoicesResult.error.message}`);
  if (claimsResult.error) throw new Error(`Insurance claims unavailable: ${claimsResult.error.message}`);
  if (admissionsResult.error) throw new Error(`Active inpatient count unavailable: ${admissionsResult.error.message}`);
  if (overdueResult.error) throw new Error(`Overdue invoice count unavailable: ${overdueResult.error.message}`);
  const monthInvoices = (monthInvoicesResult.data ?? []) as Row[];
  const payments = (todayPaymentsResult.data ?? []) as Array<{ amount?: number | null }>;
  const invoices = ensure(recentResult, 'Recent billing activity unavailable') as unknown as Row[];
  const outstanding = monthInvoices.reduce((total, row) => total + (Number(row.outstanding_amount) || 0), 0);
  const revenue = monthInvoices.reduce((total, row) => total + (Number(row.total_amount) || 0), 0);
  const avgBill = monthInvoices.length ? revenue / monthInvoices.length : 0;
  const collection = payments.reduce((total, payment) => total + (Number(payment.amount) || 0), 0);
  return {
    topMetrics: [
      { label: 'Pending Invoices', value: invoiceResult.count ?? 0, href: '/billing' },
      { label: 'Cash Collected Today', value: `GHS ${collection.toFixed(2)}`, href: '/billing' },
      { label: 'NHIS Claims Pending', value: claimsResult.count ?? 0, href: '/insurance-claims' },
      { label: 'Active Inpatients to Bill', value: admissionsResult.count ?? 0, href: '/billing/inpatients' },
    ],
    secondaryMetrics: [
      { label: 'Total Revenue (Month)', value: `GHS ${revenue.toFixed(2)}`, href: '/financial-reports' },
      { label: 'Outstanding Debt', value: `GHS ${outstanding.toFixed(2)}`, href: '/billing' },
      { label: 'Average Bill Value', value: `GHS ${avgBill.toFixed(2)}`, description: 'Current month' },
    ],
    activities: invoices.map((row) => makeActivity(row, `${row.invoice_number ? `Invoice ${row.invoice_number}` : 'Invoice'} ${row.status ?? 'updated'} for ${patientName(row)}`, `GHS ${Number(row.total_amount ?? 0).toFixed(2)}`, '/billing')),
    upcoming: [],
    alerts: overdueResult.count ? [{ id: 'overdue-invoices', title: 'Overdue Invoices (>30 Days)', detail: `${overdueResult.count} invoice(s) have been outstanding for more than 30 days.`, href: '/billing', severity: 'warning' }] : [],
  };
}

async function fetchNursing(): Promise<RoleDashboardData> {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const [admissionsResult, triageResult, alertsResult, vitalsResult, recentAdmissionsResult] = await Promise.all([
    supabase.from('admissions').select('id,status,admitted_at,ward,bed', { count: 'exact', head: true }).eq('status', 'admitted'),
    supabase.from('vital_signs').select('id,priority,recorded_at', { count: 'exact', head: true }).gte('recorded_at', start.toISOString()),
    supabase.from('vital_alerts').select('id,alert_type,severity,created_at,acknowledged_at,patients(first_name,last_name)').is('acknowledged_at', null).order('created_at', { ascending: false }).limit(10),
    supabase.from('vital_signs').select('id,recorded_at', { count: 'exact', head: true }).gte('recorded_at', start.toISOString()),
    supabase.from('admissions').select('id,status,created_at,ward,bed,patients(first_name,last_name)').order('created_at', { ascending: false }).limit(8),
  ]);
  if (admissionsResult.error) throw new Error(`Active inpatient count unavailable: ${admissionsResult.error.message}`);
  if (triageResult.error) throw new Error(`Triage count unavailable: ${triageResult.error.message}`);
  if (vitalsResult.error) throw new Error(`Vitals count unavailable: ${vitalsResult.error.message}`);
  const alerts = ensure(alertsResult, 'Vital alerts unavailable') as unknown as Row[];
  const admissions = ensure(recentAdmissionsResult, 'Recent nursing activity unavailable') as unknown as Row[];
  return {
    topMetrics: [
      { label: 'Patients in Triage', value: triageResult.count ?? 0, href: '/vitals' },
      { label: 'Available Beds', value: '—', description: 'See live bed board', href: '/ward-bed-board' },
      { label: 'Vitals Due', value: alerts.length, href: '/vitals' },
      { label: 'Admissions Today', value: admissions.filter((row) => row.created_at && Date.parse(row.created_at) >= start.getTime()).length, href: '/admissions' },
    ],
    secondaryMetrics: [
      { label: 'Total Patients in Ward', value: admissionsResult.count ?? 0, href: '/inpatient' },
      { label: 'Nurse-to-Patient Ratio', value: '—', description: 'Staffing ratios are not available in the current ward feed' },
      { label: 'Vitals Recorded Today', value: vitalsResult.count ?? 0, href: '/vitals' },
    ],
    activities: admissions.map((row) => makeActivity(row, `Patient admitted to ${row.ward ?? 'ward'}: ${patientName(row)}`, row.bed ? `Bed ${row.bed}` : '', '/inpatient')),
    upcoming: [],
    alerts: alerts.map((row) => ({ ...makeActivity(row, row.alert_type ?? 'Vital sign alert', `${patientName(row)} · ${row.severity ?? 'attention'}`, '/vitals'), severity: row.severity === 'critical' ? 'critical' : 'warning' })),
  };
}

const loaders: Record<DashboardRole, (userId?: string) => Promise<RoleDashboardData>> = {
  practitioner: fetchClinician,
  lab_technician: fetchLaboratory,
  pharmacist: fetchPharmacy,
  accountant: fetchAccounts,
  nurse: fetchNursing,
};

export function useRoleDashboardData(role: DashboardRole, userId?: string) {
  return useQuery({
    queryKey: ['role-dashboard', role, userId],
    queryFn: () => loaders[role](userId),
    enabled: Boolean(userId),
    staleTime: 30_000,
    refetchOnWindowFocus: true,
  });
}
