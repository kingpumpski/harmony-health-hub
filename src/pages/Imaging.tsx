import { ImageIcon, BellRing, Plus, CheckCircle2 } from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import { searchPatientDirectory } from '@/lib/patientDirectory';
import { toast } from '@/hooks/use-toast';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import RefreshButton from '@/components/ui/RefreshButton';
import WorklistDataTable, { type WorklistColumn, type WorklistFilter } from '@/components/workflow/WorklistDataTable';

interface ImagingOrder { id: string; patient_id: string; modality: string; study_name: string; body_site: string | null; priority: string; clinical_indication: string | null; amount: number; status: string; service_order_id: string | null; report: string | null; impression: string | null; created_at: string; patients?: { first_name: string; last_name: string } | null }
interface Patient { id: string; first_name: string; last_name: string }
export default function Imaging() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [orders, setOrders] = useState<ImagingOrder[]>([]);
  const [patientId, setPatientId] = useState('');
  const [patientSearch, setPatientSearch] = useState('');
  const [modality, setModality] = useState('X-Ray');
  const [studyName, setStudyName] = useState('');
  const [bodySite, setBodySite] = useState('');
  const [priority, setPriority] = useState('routine');
  const [indication, setIndication] = useState('');
  const [amount, setAmount] = useState(0);
  const [reports, setReports] = useState<Record<string, { report: string; impression: string }>>({});
  const [loading, setLoading] = useState(false);
  const [previousIds, setPreviousIds] = useState<Set<string>>(new Set());
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [activeSearch, setActiveSearch] = useState('');
  const [activeModality, setActiveModality] = useState('all');
  const [activePriority, setActivePriority] = useState('all');
  const [activeStatus, setActiveStatus] = useState('all');
  const [completedSearch, setCompletedSearch] = useState('');
  const [completedModality, setCompletedModality] = useState('all');
  const [completedPriority, setCompletedPriority] = useState('all');
  const [completedDate, setCompletedDate] = useState('');

  const load = useCallback(async (announce = false) => {
    if (!user?.id) return;
    setLoading(true);
    const { data, error } = await supabase.rpc('get_imaging_workspace', { _limit: 300 });
    if (error) {
      setLoading(false);
      toast({ title: 'Imaging workspace unavailable', description: error.message, variant: 'destructive' });
      return;
    }
    const workspace = (data ?? {}) as { patients?: Patient[]; orders?: ImagingOrder[] };
    const nextOrders = workspace.orders ?? [];
    if (announce && previousIds.size > 0 && nextOrders.some((order) => !previousIds.has(order.id))) playWorkflowSound('info');
    setPreviousIds(new Set(nextOrders.map((order) => order.id)));
    setPatients(workspace.patients ?? []);
    setOrders(nextOrders);
    setLastUpdated(new Date());
    setLoading(false);
  }, [user?.id]);

  useEffect(() => {
    if (!user) return;
    const imagingRoles = new Set(['admin', 'radiologist', 'radiology_technician', 'practitioner']);
    if (!user.roles.some((role) => imagingRoles.has(role))) return;
    void load();
    const refreshTimer = window.setInterval(() => void load(true), 30000);
    return () => window.clearInterval(refreshTimer);
  }, [user]);

  useEffect(() => {
    if (!user?.id) return;
    const query = patientSearch.trim();
    const timer = window.setTimeout(async () => {
      if (!query) {
        void load();
        return;
      }
      const { data, error } = await searchPatientDirectory(query, 100);
      if (error) {
        toast({ title: 'Patient search unavailable', description: error.message, variant: 'destructive' });
        return;
      }
      setPatients(data.map((patient) => ({ id: patient.id, first_name: patient.first_name, last_name: patient.last_name })));
    }, 250);
    return () => window.clearTimeout(timer);
  }, [patientSearch, user?.id, load]);

  const counters = useMemo(() => ({
    awaiting_release: orders.filter((order) => ['pending_payment_approval', 'pending_payment'].includes(order.status)).length,
    ready: orders.filter((order) => ['released', 'queued'].includes(order.status)).length,
    in_progress: orders.filter((order) => order.status === 'in_progress').length,
    completed: orders.filter((order) => order.status === 'completed').length,
    urgent: orders.filter((order) => ['urgent', 'stat'].includes(order.priority) && order.status !== 'completed').length,
  }), [orders]);



  const createOrder = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!patientId || !studyName.trim() || !user?.id) return;
    const { data, error } = await supabase.rpc('create_imaging_order_with_payment_gate' as never, { _patient_id: patientId, _encounter_id: null, _modality: modality, _study_name: studyName, _body_site: bodySite || null, _priority: priority, _clinical_indication: indication || null, _amount: amount } as never);
    if (error) { playWorkflowSound('critical'); return toast({ title: 'Failed', description: error.message, variant: 'destructive' }); }
    const result = data as { status?: string } | null;
    playWorkflowSound(result?.status === 'released' ? 'success' : 'info');
    toast({ title: result?.status === 'released' ? 'Imaging request released' : 'Payment approval required', description: result?.status === 'released' ? 'The imaging department can proceed.' : 'Accounts must release the imaging order before it can be performed.' });
    setPatientId(''); setPatientSearch(''); setStudyName(''); setBodySite(''); setIndication(''); setAmount(0); setPriority('routine');
    void load();
  };

  const start = async (order: ImagingOrder) => {
    const { error } = await supabase.rpc('start_imaging_order' as never, { _imaging_order_id: order.id } as never);
    if (error) { playWorkflowSound('critical'); toast({ title: 'Cannot start imaging', description: error.message, variant: 'destructive' }); return; }
    playWorkflowSound('success'); toast({ title: 'Imaging started' }); void load();
  };

  const saveReport = async (order: ImagingOrder) => {
    const value = reports[order.id] ?? { report: '', impression: '' };
    if (!value.report.trim() && !value.impression.trim()) return;
    const { error } = await supabase.rpc('complete_imaging_order' as never, { _imaging_order_id: order.id, _report: value.report, _impression: value.impression } as never);
    if (error) { playWorkflowSound('critical'); return toast({ title: 'Report failed', description: error.message, variant: 'destructive' }); }
    playWorkflowSound('success'); toast({ title: 'Imaging report saved' }); void load();
  };

  const patientName = (order: ImagingOrder) => {
    if (order.patients) return order.patients.first_name + ' ' + order.patients.last_name;
    const patient = patients.find((item) => item.id === order.patient_id);
    return patient ? patient.first_name + ' ' + patient.last_name : 'Unknown patient';
  };

  const activeOrders = orders.filter((order) => order.status !== 'completed');
  const activePatientRows = useMemo(() => {
    const byPatient = new Map<string, ImagingOrder>();
    activeOrders.forEach((order) => {
      const current = byPatient.get(order.patient_id);
      if (!current || new Date(order.created_at).getTime() > new Date(current.created_at).getTime()) byPatient.set(order.patient_id, order);
    });
    return Array.from(byPatient.values()).map((order) => ({ patient_id: order.patient_id, patient_name: patientName(order), latest_order: order, active_count: activeOrders.filter((item) => item.patient_id === order.patient_id).length }));
  }, [orders, patients]);

  const filteredActivePatients = useMemo(() => activePatientRows.filter((row) => {
    const q = activeSearch.trim().toLowerCase();
    return (!q || row.patient_name.toLowerCase().includes(q) || row.latest_order.study_name.toLowerCase().includes(q) || row.patient_id.toLowerCase().includes(q)) &&
      (activeModality === 'all' || row.latest_order.modality === activeModality) &&
      (activePriority === 'all' || row.latest_order.priority === activePriority) &&
      (activeStatus === 'all' || row.latest_order.status === activeStatus);
  }), [activePatientRows, activeModality, activePriority, activeSearch, activeStatus]);

  const filteredCompletedOrders = useMemo(() => orders.filter((order) => {
    if (order.status !== 'completed') return false;
    const q = completedSearch.trim().toLowerCase();
    return (!q || patientName(order).toLowerCase().includes(q) || order.study_name.toLowerCase().includes(q) || order.patient_id.toLowerCase().includes(q)) &&
      (completedModality === 'all' || order.modality === completedModality) &&
      (completedPriority === 'all' || order.priority === completedPriority) &&
      (!completedDate || order.created_at.slice(0, 10) === completedDate);
  }), [orders, completedModality, completedPriority, completedSearch, completedDate, patients]);

  const modalityOptions = ['X-Ray', 'Ultrasound', 'CT', 'MRI', 'Mammography', 'Fluoroscopy'].map((value) => ({ value, label: value }));
  const priorityOptions = [{ value: 'routine', label: 'Routine' }, { value: 'urgent', label: 'Urgent' }, { value: 'stat', label: 'STAT' }];

  const activeColumns: WorklistColumn<typeof activePatientRows[number]>[] = [
    { key: 'patient', label: 'Patient', required: true, render: (row) => <div><p className='font-medium'>{row.patient_name}</p><p className='text-[11px] text-muted-foreground'>Patient ID: {row.patient_id.slice(0, 8)}…</p></div>, sortValue: (row) => row.patient_name },
    { key: 'study', label: 'Latest study', render: (row) => <div><p className='font-medium'>{row.latest_order.study_name}</p><p className='text-[11px] text-muted-foreground'>{row.latest_order.modality} · {row.latest_order.body_site || 'No body site'}</p></div>, sortValue: (row) => row.latest_order.created_at },
    { key: 'status', label: 'Status', render: (row) => <span className='rounded-full bg-muted px-2.5 py-1 text-[11px] font-semibold capitalize'>{row.latest_order.status.replaceAll('_', ' ')}</span>, sortValue: (row) => row.latest_order.status },
    { key: 'priority', label: 'Priority', render: (row) => <span className={'rounded-full px-2.5 py-1 text-[11px] font-semibold ' + (['urgent','stat'].includes(row.latest_order.priority) ? 'bg-critical/10 text-critical' : 'bg-muted text-muted-foreground')}>{row.latest_order.priority.toUpperCase()}</span>, sortValue: (row) => row.latest_order.priority },
    { key: 'orders', label: 'Active orders', render: (row) => <span className='font-semibold'>{row.active_count}</span>, sortValue: (row) => row.active_count },
    { key: 'created', label: 'Latest requested', render: (row) => <span className='text-xs text-muted-foreground'>{new Date(row.latest_order.created_at).toLocaleString()}</span>, sortValue: (row) => row.latest_order.created_at },
  ];

  const completedColumns: WorklistColumn<ImagingOrder>[] = [
    { key: 'patient', label: 'Patient', required: true, render: (row) => <div><p className='font-medium'>{patientName(row)}</p><p className='text-[11px] text-muted-foreground'>Patient ID: {row.patient_id.slice(0, 8)}…</p></div>, sortValue: (row) => patientName(row) },
    { key: 'study', label: 'Study', render: (row) => <div><p className='font-medium'>{row.study_name}</p><p className='text-[11px] text-muted-foreground'>{row.modality} · {row.body_site || 'No body site'}</p></div>, sortValue: (row) => row.study_name },
    { key: 'priority', label: 'Priority', render: (row) => <span className='rounded-full bg-muted px-2.5 py-1 text-[11px] font-semibold'>{row.priority.toUpperCase()}</span>, sortValue: (row) => row.priority },
    { key: 'completed', label: 'Completed', render: (row) => <span className='text-xs text-muted-foreground'>{new Date(row.created_at).toLocaleString()}</span>, sortValue: (row) => row.created_at },
    { key: 'impression', label: 'Impression', defaultVisible: false, render: (row) => <span className='line-clamp-2 text-xs text-muted-foreground'>{row.impression || 'Not recorded'}</span> },
  ];

  const activeFilters: WorklistFilter[] = [
    { key: 'search', label: 'Patient / study', value: activeSearch, onChange: setActiveSearch, placeholder: 'Search patient or study' },
    { key: 'modality', label: 'Modality', value: activeModality, onChange: setActiveModality, options: [{ value: 'all', label: 'All modalities' }, ...modalityOptions] },
    { key: 'priority', label: 'Priority', value: activePriority, onChange: setActivePriority, options: [{ value: 'all', label: 'All priorities' }, ...priorityOptions] },
    { key: 'status', label: 'Status', value: activeStatus, onChange: setActiveStatus, options: [{ value: 'all', label: 'All active statuses' }, { value: 'pending_payment', label: 'Pending payment' }, { value: 'pending_payment_approval', label: 'Awaiting approval' }, { value: 'queued', label: 'Queued' }, { value: 'released', label: 'Released' }, { value: 'in_progress', label: 'In progress' }] },
  ];
  const completedFilters: WorklistFilter[] = [
    { key: 'search', label: 'Patient / study', value: completedSearch, onChange: setCompletedSearch, placeholder: 'Search patient or study' },
    { key: 'modality', label: 'Modality', value: completedModality, onChange: setCompletedModality, options: [{ value: 'all', label: 'All modalities' }, ...modalityOptions] },
    { key: 'priority', label: 'Priority', value: completedPriority, onChange: setCompletedPriority, options: [{ value: 'all', label: 'All priorities' }, ...priorityOptions] },
    { key: 'date', label: 'Order date', value: completedDate, onChange: setCompletedDate, type: 'date' },
  ];

  return (
    <OperationalWorklistShell icon={ImageIcon} eyebrow='Diagnostics · Radiology' title='Radiology Workspace' description='Manage active patients, imaging requests, reporting and completed studies from one role-scoped radiology worklist.' actions={<RefreshButton onClick={() => { playWorkflowSound('info'); void load(); }} loading={loading} label='Refresh radiology workspace' />} counters={[
      { label: 'Active patients', value: activePatientRows.length, surface: 'bg-info/5', tone: 'text-info' },
      { label: 'Awaiting Accounts', value: counters.awaiting_release, surface: 'bg-warning/5', tone: 'text-warning' },
      { label: 'Ready', value: counters.ready, surface: 'bg-info/5', tone: 'text-info' },
      { label: 'In progress', value: counters.in_progress, surface: 'bg-primary/5', tone: 'text-primary' },
      { label: 'Completed', value: counters.completed, surface: 'bg-success/5', tone: 'text-success' },
    ]} beforeList={<>
      {counters.urgent > 0 && <div className='rounded-xl border border-critical/30 bg-critical/5 p-3 flex items-center gap-2 text-sm' role='alert'><BellRing className='w-4 h-4 text-critical shrink-0' aria-hidden='true' /><span className='font-medium'>{counters.urgent} urgent/STAT case{counters.urgent === 1 ? '' : 's'} require attention.</span></div>}
      <section className='card-medical p-5'><div className='flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between'><div><h2 className='font-semibold flex items-center gap-2'><Plus className='w-4 h-4' aria-hidden='true' /> New imaging request</h2><p className='mt-1 text-xs text-muted-foreground'>Chargeable imaging remains held until Accounts releases payment or an authorised override is recorded.</p></div><span className='rounded-full border border-primary/20 bg-primary/5 px-2.5 py-1 text-[10px] font-medium text-primary'>Diagnostic workflow</span></div>
        <form onSubmit={createOrder} className='mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-3'>
          <div><label htmlFor='imaging-patient-search' className='mb-1 block text-xs font-semibold'>Search patient by name or code</label><input id='imaging-patient-search' value={patientSearch} onChange={e => setPatientSearch(e.target.value)} placeholder='Type a name or patient code…' className='input-medical w-full mb-2' autoComplete='off' /><label htmlFor='imaging-patient' className='mb-1 block text-xs font-semibold'>Patient <span className='text-critical'>*</span></label><select id='imaging-patient' value={patientId} onChange={e => setPatientId(e.target.value)} className='input-medical w-full' required><option value=''>Select patient…</option>{patients.map(p => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}</select></div>
          <div><label htmlFor='imaging-modality' className='mb-1 block text-xs font-semibold'>Modality</label><select id='imaging-modality' value={modality} onChange={e => setModality(e.target.value)} className='input-medical w-full'>{modalityOptions.map(option => <option key={option.value}>{option.value}</option>)}</select></div>
          <div><label htmlFor='imaging-study' className='mb-1 block text-xs font-semibold'>Study name <span className='text-critical'>*</span></label><input id='imaging-study' value={studyName} onChange={e => setStudyName(e.target.value)} placeholder='Study name' className='input-medical w-full' required /></div>
          <div><label htmlFor='imaging-body-site' className='mb-1 block text-xs font-semibold'>Body site</label><input id='imaging-body-site' value={bodySite} onChange={e => setBodySite(e.target.value)} placeholder='Body site' className='input-medical w-full' /></div>
          <div><label htmlFor='imaging-priority' className='mb-1 block text-xs font-semibold'>Priority</label><select id='imaging-priority' value={priority} onChange={e => setPriority(e.target.value)} className='input-medical w-full'>{priorityOptions.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div>
          <div><label htmlFor='imaging-amount' className='mb-1 block text-xs font-semibold'>Charge (GHS)</label><input id='imaging-amount' type='number' min={0} step='0.01' value={amount || ''} onChange={e => setAmount(Number(e.target.value))} placeholder='0 means billing tariff required' className='input-medical w-full' /></div>
          <div className='md:col-span-2 lg:col-span-3'><label htmlFor='imaging-indication' className='mb-1 block text-xs font-semibold'>Clinical indication</label><textarea id='imaging-indication' value={indication} onChange={e => setIndication(e.target.value)} placeholder='Clinical indication' className='input-medical w-full' rows={3} /></div>
          <div className='md:col-span-2 lg:col-span-3 flex justify-end'><button type='submit' className='btn-primary inline-flex items-center gap-2'><Plus className='w-4 h-4' aria-hidden='true' /> {amount > 0 ? 'Request payment approval' : 'Create imaging request'}</button></div>
        </form></section>
    </>} listTitle='Radiology worklists' listDescription='Standardized filter panels, role-safe columns and the shared refresh control are used across the operational tables.' listMeta={lastUpdated ? 'Last updated ' + lastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : 'Not synced yet'} bareList loading={false} empty={false}>
      <div className='space-y-6'>
        <WorklistDataTable title='Active patient list' description='Patients with one or more imaging orders that are not yet completed.' rows={filteredActivePatients} columns={activeColumns} getRowId={(row) => row.patient_id} filters={activeFilters} onResetFilters={() => { setActiveSearch(''); setActiveModality('all'); setActivePriority('all'); setActiveStatus('all'); }} onRefresh={() => void load()} refreshing={loading} lastUpdated={lastUpdated} pageSize={20} emptyMessage='No active radiology patients match the current filters.' rowActions={(row) => row.latest_order.status === 'released' ? <button type='button' className='btn-primary text-xs' onClick={() => void start(row.latest_order)}>Start</button> : <span className='text-xs text-muted-foreground'>No action</span>} columnPreferenceKey='radiology-active-patients' />
        <WorklistDataTable title='Completed order list' description='Completed imaging studies and final reporting context.' rows={filteredCompletedOrders} columns={completedColumns} getRowId={(row) => row.id} filters={completedFilters} onResetFilters={() => { setCompletedSearch(''); setCompletedModality('all'); setCompletedPriority('all'); setCompletedDate(''); }} onRefresh={() => void load()} refreshing={loading} lastUpdated={lastUpdated} pageSize={20} emptyMessage='No completed radiology orders match the current filters.' columnPreferenceKey='radiology-completed-orders' />
        {filteredActivePatients.some((row) => row.latest_order.status === 'in_progress') && <section className='card-medical p-4'><h2 className='font-semibold flex items-center gap-2'><CheckCircle2 className='w-4 h-4' aria-hidden='true' /> Reporting workspace</h2><p className='mt-1 text-xs text-muted-foreground'>Complete in-progress studies here without losing the active patient worklist context.</p><div className='mt-4 space-y-3'>{filteredActivePatients.filter((row) => row.latest_order.status === 'in_progress').map((row) => { const order = row.latest_order; const value = reports[order.id] ?? { report: order.report ?? '', impression: order.impression ?? '' }; return <div key={order.id} className='rounded-xl border border-border p-4'><div className='flex flex-wrap items-center justify-between gap-2'><div><p className='font-medium'>{row.patient_name} · {order.study_name}</p><p className='text-xs text-muted-foreground'>{order.modality} · {order.priority.toUpperCase()}</p></div><span className='rounded-full bg-primary/10 px-2.5 py-1 text-[11px] font-semibold text-primary'>In progress</span></div><div className='mt-3 grid gap-3 lg:grid-cols-2'><div><label htmlFor={'imaging-report-' + order.id} className='mb-1 block text-xs font-semibold'>Radiology report</label><textarea id={'imaging-report-' + order.id} value={value.report} onChange={e => setReports({ ...reports, [order.id]: { ...value, report: e.target.value } })} rows={4} className='input-medical w-full' /></div><div><label htmlFor={'imaging-impression-' + order.id} className='mb-1 block text-xs font-semibold'>Impression</label><textarea id={'imaging-impression-' + order.id} value={value.impression} onChange={e => setReports({ ...reports, [order.id]: { ...value, impression: e.target.value } })} rows={4} className='input-medical w-full' /></div></div><div className='mt-3 flex justify-end'><button type='button' onClick={() => void saveReport(order)} className='btn-primary inline-flex items-center gap-2 text-xs'><CheckCircle2 className='w-4 h-4' aria-hidden='true' /> Save report & complete</button></div></div>; })}</div></section>}
      </div>
    </OperationalWorklistShell>
  );
}
