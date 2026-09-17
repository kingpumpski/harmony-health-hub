import { useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
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
    setLoading(true);
    const [{ data: p }, { data: o }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name').limit(300),
      supabase.from('imaging_orders').select('*, patients(first_name,last_name)').order('created_at', { ascending: false }).limit(100),
    ]);
    const nextOrders = (o ?? []) as ImagingOrder[];
    if (announce && previousIds.size > 0 && nextOrders.some((order) => !previousIds.has(order.id))) playWorkflowSound('info');
    setPreviousIds(new Set(nextOrders.map((order) => order.id)));
    setPatients((p ?? []) as Patient[]);
    setOrders(nextOrders);
    setLoading(false);
  };

  useEffect(() => { void load(); }, []);
  useEffect(() => {
    const channel = supabase.channel('imaging-workflow-live')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'imaging_orders' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, () => void load())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, []);

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

  return <div className="space-y-6 animate-fade-in">
    <header className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><ImageIcon className="w-6 h-6 text-primary" /> Imaging</h1><p className="text-muted-foreground">Request, release, perform and report diagnostic imaging through the central service queue.</p></div><button onClick={() => { playWorkflowSound('info'); void load(); }} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="w-4 h-4" />{loading ? 'Refreshing...' : 'Refresh'}</button></header>
    <section className="grid grid-cols-2 lg:grid-cols-5 gap-3">
      {[
        { key: 'awaiting_release' as QueueFilter, label: 'Awaiting Accounts', value: counters.awaiting_release, surface: 'bg-warning/5', tone: 'text-warning' },
        { key: 'ready' as QueueFilter, label: 'Ready for imaging', value: counters.ready, surface: 'bg-info/5', tone: 'text-info' },
        { key: 'in_progress' as QueueFilter, label: 'In progress', value: counters.in_progress, surface: 'bg-primary/5', tone: 'text-primary' },
        { key: 'completed' as QueueFilter, label: 'Completed', value: counters.completed, surface: 'bg-success/5', tone: 'text-success' },
        { key: 'all' as QueueFilter, label: 'Urgent / STAT', value: counters.urgent, surface: 'bg-critical/5', tone: 'text-critical' },
      ].map((counter) => <button key={counter.label} type="button" onClick={() => setFilter(counter.key)} className={`card-medical p-4 text-left transition-all hover:-translate-y-1 ${counter.surface} ${filter === counter.key ? 'ring-2 ring-primary/30' : ''}`}><p className="text-xs text-muted-foreground">{counter.label}</p><p className={`text-2xl font-bold ${counter.tone} ${counter.value > 0 && counter.key !== 'completed' ? 'animate-pulse' : ''}`}>{counter.value}</p></button>)}
    </section>
    {counters.urgent > 0 && <div className="rounded-xl border border-critical/30 bg-critical/5 p-3 flex items-center gap-2 text-sm"><BellRing className="w-4 h-4 text-critical" /><span className="font-medium">{counters.urgent} urgent/STAT imaging case{counters.urgent === 1 ? '' : 's'} require{counters.urgent === 1 ? 's' : ''} attention.</span></div>}
    <div className="rounded-xl border border-primary/20 bg-primary/5 p-3 flex items-start gap-2 text-sm"><CreditCard className="w-4 h-4 text-primary mt-0.5 shrink-0" /><p className="text-muted-foreground">Chargeable imaging is held until Accounts releases payment or an authorised override is recorded. If a service reaches billing without a tariff, Accounts can resolve it through the Tariff Adjustments worklist before release.</p></div>
    <form onSubmit={createOrder} className="card-medical p-5 space-y-3">
      <h2 className="font-semibold">New imaging request</h2>
      <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
        <select value={patientId} onChange={e => setPatientId(e.target.value)} className="input-medical" required><option value="">Select patient…</option>{patients.map(p => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}</select>
        <select value={modality} onChange={e => setModality(e.target.value)} className="input-medical"><option>X-Ray</option><option>Ultrasound</option><option>CT</option><option>MRI</option><option>Mammography</option><option>Fluoroscopy</option></select>
        <input value={studyName} onChange={e => setStudyName(e.target.value)} placeholder="Study name" className="input-medical" required />
        <input value={bodySite} onChange={e => setBodySite(e.target.value)} placeholder="Body site" className="input-medical" />
        <select value={priority} onChange={e => setPriority(e.target.value)} className="input-medical"><option value="routine">Routine</option><option value="urgent">Urgent</option><option value="stat">STAT</option></select>
        <input type="number" min={0} step="0.01" value={amount || ''} onChange={e => setAmount(Number(e.target.value))} placeholder="Charge (GHS) — 0 means billing tariff required" className="input-medical" />
      </div>
      <textarea value={indication} onChange={e => setIndication(e.target.value)} placeholder="Clinical indication" className="input-medical w-full" rows={3} />
      <button className="btn-primary inline-flex items-center gap-2"><Plus className="w-4 h-4" /> {amount > 0 ? 'Request payment approval' : 'Create imaging request'}</button>
    </form>
    <div className="card-medical p-5"><div className="flex items-center justify-between mb-3"><div><h2 className="font-semibold">Imaging queue</h2><p className="text-xs text-muted-foreground">{visibleOrders.length} case{visibleOrders.length === 1 ? '' : 's'} shown · filter: {filter.replace('_', ' ')}</p></div></div><div className="space-y-3">{visibleOrders.map(order => { const value = reports[order.id] ?? { report: order.report ?? '', impression: order.impression ?? '' }; const urgent = ['urgent', 'stat'].includes(order.priority) && order.status !== 'completed'; return <div key={order.id} className={`rounded-xl border p-4 space-y-3 ${urgent ? 'border-critical/30 bg-critical/5' : 'border-border'}`}><div className="flex flex-wrap justify-between gap-3"><div><p className="font-medium">{order.study_name} · {order.modality}</p><p className="text-xs text-muted-foreground">{order.patients?.first_name} {order.patients?.last_name} · {order.body_site || '—'} · {order.priority}</p></div><div className="flex items-center gap-2"><span className="text-xs font-semibold px-2 py-1 rounded-full bg-muted">{order.status}</span>{urgent && <AlertTriangle className="w-4 h-4 text-critical" />}</div></div>{order.status === 'released' && <button onClick={() => void start(order)} className="btn-primary text-xs">Start imaging</button>}{['in_progress','completed'].includes(order.status) && <div className="space-y-2"><textarea value={value.report} onChange={e => setReports({ ...reports, [order.id]: { ...value, report: e.target.value } })} placeholder="Radiology report" rows={3} className="input-medical w-full" /><textarea value={value.impression} onChange={e => setReports({ ...reports, [order.id]: { ...value, impression: e.target.value } })} placeholder="Impression" rows={2} className="input-medical w-full" />{order.status !== 'completed' && <button onClick={() => void saveReport(order)} className="btn-primary inline-flex items-center gap-2 text-xs"><CheckCircle2 className="w-4 h-4" /> Save report & complete</button>}</div>}</div>; })}{visibleOrders.length === 0 && <p className="text-sm text-muted-foreground py-6 text-center">No imaging orders match this queue.</p>}</div></div>
  </div>;
}
