import { useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import { toast } from '@/hooks/use-toast';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { AlertTriangle, CreditCard, Image as ImageIcon, Plus, CheckCircle2, RefreshCw, BellRing } from 'lucide-react';

interface ImagingOrder { id: string; patient_id: string; modality: string; study_name: string; body_site: string | null; priority: string; clinical_indication: string | null; amount: number; status: string; service_order_id: string | null; report: string | null; impression: string | null; created_at: string; patients?: { first_name: string; last_name: string } | null }
interface Patient { id: string; first_name: string; last_name: string }
const queueFilters = ['all', 'awaiting_release', 'ready', 'in_progress', 'completed'] as const;
type QueueFilter = typeof queueFilters[number];

export default function Imaging() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [orders, setOrders] = useState<ImagingOrder[]>([]);
  const [patientId, setPatientId] = useState('');
  const [modality, setModality] = useState('X-Ray');
  const [studyName, setStudyName] = useState('');
  const [bodySite, setBodySite] = useState('');
  const [priority, setPriority] = useState('routine');
  const [indication, setIndication] = useState('');
  const [amount, setAmount] = useState(0);
  const [reports, setReports] = useState<Record<string, { report: string; impression: string }>>({});
  const [filter, setFilter] = useState<QueueFilter>('all');
  const [loading, setLoading] = useState(false);
  const [previousIds, setPreviousIds] = useState<Set<string>>(new Set());

  const load = async (announce = false) => {
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
    setLoading(false);
  };

  useEffect(() => {
    if (!user) return;
    const imagingRoles = new Set(['admin', 'radiologist', 'radiology_technician', 'practitioner']);
    if (!user.roles.some((role) => imagingRoles.has(role))) return;
    void load();
    const refreshTimer = window.setInterval(() => void load(true), 30000);
    return () => window.clearInterval(refreshTimer);
  }, [user]);

  const counters = useMemo(() => ({
    awaiting_release: orders.filter((order) => ['pending_payment_approval', 'pending_payment'].includes(order.status)).length,
    ready: orders.filter((order) => ['released', 'queued'].includes(order.status)).length,
    in_progress: orders.filter((order) => order.status === 'in_progress').length,
    completed: orders.filter((order) => order.status === 'completed').length,
    urgent: orders.filter((order) => ['urgent', 'stat'].includes(order.priority) && order.status !== 'completed').length,
  }), [orders]);

  const visibleOrders = useMemo(() => orders.filter((order) => {
    if (filter === 'awaiting_release') return ['pending_payment_approval', 'pending_payment'].includes(order.status);
    if (filter === 'ready') return ['released', 'queued'].includes(order.status);
    if (filter === 'in_progress') return order.status === 'in_progress';
    if (filter === 'completed') return order.status === 'completed';
    return true;
  }), [filter, orders]);

  const createOrder = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!patientId || !studyName.trim() || !user?.id) return;
    const { data, error } = await supabase.rpc('create_imaging_order_with_payment_gate' as never, { _patient_id: patientId, _encounter_id: null, _modality: modality, _study_name: studyName, _body_site: bodySite || null, _priority: priority, _clinical_indication: indication || null, _amount: amount } as never);
    if (error) { playWorkflowSound('critical'); return toast({ title: 'Failed', description: error.message, variant: 'destructive' }); }
    const result = data as { status?: string } | null;
    playWorkflowSound(result?.status === 'released' ? 'success' : 'info');
    toast({ title: result?.status === 'released' ? 'Imaging request released' : 'Payment approval required', description: result?.status === 'released' ? 'The imaging department can proceed.' : 'Accounts must release the imaging order before it can be performed.' });
    setPatientId(''); setStudyName(''); setBodySite(''); setIndication(''); setAmount(0); setPriority('routine');
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

  return (
    <OperationalWorklistShell
      icon={ImageIcon}
      eyebrow="Diagnostics · Imaging"
      title="Imaging Workspace"
      description="Request, release, perform and report diagnostic imaging through one central service queue with payment and urgent-case visibility."
      actions={(
        <button type="button" onClick={() => { playWorkflowSound('info'); void load(); }} disabled={loading} className="btn-secondary inline-flex items-center gap-2" aria-label="Refresh imaging workspace">
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" /> {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      )}
      counters={[
        { label: 'Awaiting Accounts', value: counters.awaiting_release, surface: 'bg-warning/5', tone: 'text-warning' },
        { label: 'Ready for imaging', value: counters.ready, surface: 'bg-info/5', tone: 'text-info' },
        { label: 'In progress', value: counters.in_progress, surface: 'bg-primary/5', tone: 'text-primary' },
        { label: 'Completed', value: counters.completed, surface: 'bg-success/5', tone: 'text-success' },
        { label: 'Urgent / STAT', value: counters.urgent, surface: 'bg-critical/5', tone: 'text-critical' },
      ]}
      beforeList={(
        <>
          {counters.urgent > 0 && (
            <div className="rounded-xl border border-critical/30 bg-critical/5 p-3 flex items-center gap-2 text-sm" role="alert">
              <BellRing className="w-4 h-4 text-critical shrink-0" aria-hidden="true" />
              <span className="font-medium">{counters.urgent} urgent/STAT imaging case{counters.urgent === 1 ? '' : 's'} require{counters.urgent === 1 ? 's' : ''} attention.</span>
            </div>
          )}
          <section className="card-medical p-5">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" aria-hidden="true" /> New imaging request</h2>
                <p className="mt-1 text-xs text-muted-foreground">Chargeable imaging remains held until Accounts releases payment or an authorised override is recorded.</p>
              </div>
              <span className="rounded-full border border-primary/20 bg-primary/5 px-2.5 py-1 text-[10px] font-medium text-primary">Diagnostic workflow</span>
            </div>
            <div className="mt-3 rounded-xl border border-primary/20 bg-primary/5 p-3 flex items-start gap-2 text-xs">
              <CreditCard className="w-4 h-4 text-primary mt-0.5 shrink-0" aria-hidden="true" />
              <p className="text-muted-foreground">If a service reaches billing without a tariff, Accounts can resolve it through the Tariff Adjustments worklist before release.</p>
            </div>
            <form onSubmit={createOrder} className="mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-3">
              <div>
                <label htmlFor="imaging-patient" className="mb-1 block text-xs font-semibold">Patient <span className="text-critical">*</span></label>
                <select id="imaging-patient" value={patientId} onChange={e => setPatientId(e.target.value)} className="input-medical w-full" required><option value="">Select patient…</option>{patients.map(p => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}</select>
              </div>
              <div>
                <label htmlFor="imaging-modality" className="mb-1 block text-xs font-semibold">Modality</label>
                <select id="imaging-modality" value={modality} onChange={e => setModality(e.target.value)} className="input-medical w-full"><option>X-Ray</option><option>Ultrasound</option><option>CT</option><option>MRI</option><option>Mammography</option><option>Fluoroscopy</option></select>
              </div>
              <div>
                <label htmlFor="imaging-study" className="mb-1 block text-xs font-semibold">Study name <span className="text-critical">*</span></label>
                <input id="imaging-study" value={studyName} onChange={e => setStudyName(e.target.value)} placeholder="Study name" className="input-medical w-full" required />
              </div>
              <div>
                <label htmlFor="imaging-body-site" className="mb-1 block text-xs font-semibold">Body site</label>
                <input id="imaging-body-site" value={bodySite} onChange={e => setBodySite(e.target.value)} placeholder="Body site" className="input-medical w-full" />
              </div>
              <div>
                <label htmlFor="imaging-priority" className="mb-1 block text-xs font-semibold">Priority</label>
                <select id="imaging-priority" value={priority} onChange={e => setPriority(e.target.value)} className="input-medical w-full"><option value="routine">Routine</option><option value="urgent">Urgent</option><option value="stat">STAT</option></select>
              </div>
              <div>
                <label htmlFor="imaging-amount" className="mb-1 block text-xs font-semibold">Charge (GHS)</label>
                <input id="imaging-amount" type="number" min={0} step="0.01" value={amount || ''} onChange={e => setAmount(Number(e.target.value))} placeholder="0 means billing tariff required" className="input-medical w-full" />
              </div>
              <div className="md:col-span-2 lg:col-span-3">
                <label htmlFor="imaging-indication" className="mb-1 block text-xs font-semibold">Clinical indication</label>
                <textarea id="imaging-indication" value={indication} onChange={e => setIndication(e.target.value)} placeholder="Clinical indication" className="input-medical w-full" rows={3} />
              </div>
              <div className="md:col-span-2 lg:col-span-3 flex justify-end">
                <button type="submit" className="btn-primary inline-flex items-center gap-2"><Plus className="w-4 h-4" aria-hidden="true" /> {amount > 0 ? 'Request payment approval' : 'Create imaging request'}</button>
              </div>
            </form>
          </section>
          <section className="card-medical p-4">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 className="font-semibold">Queue filter</h2>
                <p className="text-xs text-muted-foreground">Choose the operational stage to focus the worklist.</p>
              </div>
              <div className="flex flex-wrap gap-2" role="group" aria-label="Imaging queue filters">
                {[
                  { key: 'all' as QueueFilter, label: 'All' },
                  { key: 'awaiting_release' as QueueFilter, label: 'Awaiting Accounts' },
                  { key: 'ready' as QueueFilter, label: 'Ready' },
                  { key: 'in_progress' as QueueFilter, label: 'In progress' },
                  { key: 'completed' as QueueFilter, label: 'Completed' },
                ].map((option) => (
                  <button type="button" key={option.key} onClick={() => setFilter(option.key)} className={`rounded-full border px-3 py-1.5 text-xs font-medium transition-colors ${filter === option.key ? 'border-primary bg-primary/10 text-primary' : 'border-border hover:bg-muted/50'}`} aria-pressed={filter === option.key}>{option.label}</button>
                ))}
              </div>
            </div>
          </section>
        </>
      )}
      listTitle="Imaging worklist"
      listDescription="Review patient, study, priority, payment state and reporting progress without leaving the central queue."
      listMeta={`${visibleOrders.length} case${visibleOrders.length === 1 ? '' : 's'} shown · ${filter.replace('_', ' ')}`}
      loading={loading}
      empty={visibleOrders.length === 0}
      emptyTitle="No imaging orders match this queue"
      emptyDescription="Create a new imaging request above or change the queue filter."
    >
      {visibleOrders.map(order => {
        const value = reports[order.id] ?? { report: order.report ?? '', impression: order.impression ?? '' };
        const urgent = ['urgent', 'stat'].includes(order.priority) && order.status !== 'completed';
        return (
          <div key={order.id} className={`p-4 transition-colors ${urgent ? 'bg-critical/5' : ''}`}>
            <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-medium">{order.study_name} · {order.modality}</p>
                  {urgent && <span className="rounded-full bg-critical/10 px-2 py-0.5 text-[10px] font-semibold text-critical">Urgent attention</span>}
                </div>
                <p className="mt-1 text-xs text-muted-foreground">{order.patients?.first_name} {order.patients?.last_name} · {order.body_site || '—'} · {new Date(order.created_at).toLocaleString()}</p>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-muted capitalize">{order.status.replace('_', ' ')}</span>
                {urgent && <AlertTriangle className="w-4 h-4 text-critical" aria-hidden="true" />}
              </div>
            </div>
            <div className="mt-3 flex flex-wrap gap-2">
              {order.status === 'released' && <button type="button" onClick={() => void start(order)} className="btn-primary text-xs">Start imaging</button>}
              {['in_progress','completed'].includes(order.status) && <div className="w-full space-y-2">
                <label htmlFor={`imaging-report-${order.id}`} className="sr-only">Radiology report</label>
                <textarea id={`imaging-report-${order.id}`} value={value.report} onChange={e => setReports({ ...reports, [order.id]: { ...value, report: e.target.value } })} placeholder="Radiology report" rows={3} className="input-medical w-full" />
                <label htmlFor={`imaging-impression-${order.id}`} className="sr-only">Impression</label>
                <textarea id={`imaging-impression-${order.id}`} value={value.impression} onChange={e => setReports({ ...reports, [order.id]: { ...value, impression: e.target.value } })} placeholder="Impression" rows={2} className="input-medical w-full" />
                {order.status !== 'completed' && <button type="button" onClick={() => void saveReport(order)} className="btn-primary inline-flex items-center gap-2 text-xs"><CheckCircle2 className="w-4 h-4" aria-hidden="true" /> Save report & complete</button>}
              </div>}
            </div>
          </div>
        );
      })}
    </OperationalWorklistShell>
  );
}