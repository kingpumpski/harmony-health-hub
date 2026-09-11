import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { CreditCard, Image as ImageIcon, Plus, CheckCircle2 } from 'lucide-react';
import { markServiceOrderInProgress, completeServiceOrder } from '@/lib/workflow';

interface ImagingOrder {
  id: string;
  patient_id: string;
  modality: string;
  study_name: string;
  body_site: string | null;
  priority: string;
  clinical_indication: string | null;
  amount: number;
  status: string;
  service_order_id: string | null;
  report: string | null;
  impression: string | null;
  created_at: string;
  patients?: { first_name: string; last_name: string } | null;
}

interface Patient { id: string; first_name: string; last_name: string }

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

  const load = async () => {
    const [{ data: p }, { data: o }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name').limit(300),
      supabase.from('imaging_orders').select('*, patients(first_name,last_name)').order('created_at', { ascending: false }).limit(100),
    ]);
    setPatients((p ?? []) as Patient[]);
    setOrders((o ?? []) as ImagingOrder[]);
  };

  useEffect(() => { void load(); }, []);

  const createOrder = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!patientId || !studyName.trim() || !user?.id) return;
    const { data, error } = await supabase.rpc('create_imaging_order_with_payment_gate' as never, {
      _patient_id: patientId,
      _modality: modality,
      _study_name: studyName,
      _body_site: bodySite || null,
      _priority: priority,
      _clinical_indication: indication || null,
      _amount: amount,
    } as never);
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    const result = data as { status?: string } | null;
    toast({ title: result?.status === 'released' ? 'Imaging request released' : 'Payment approval required', description: result?.status === 'released' ? 'The imaging department can proceed.' : 'Accounts must release the imaging order before it can be performed.' });
    setPatientId(''); setStudyName(''); setBodySite(''); setIndication(''); setAmount(0); setPriority('routine');
    void load();
  };

  const start = async (order: ImagingOrder) => {
    if (!order.service_order_id) return;
    try { await markServiceOrderInProgress(order.service_order_id); await supabase.from('imaging_orders').update({ status: 'in_progress', performed_by: user?.id }).eq('id', order.id); void load(); }
    catch (error) { toast({ title: 'Cannot start imaging', description: error instanceof Error ? error.message : 'Payment release is required.', variant: 'destructive' }); }
  };

  const saveReport = async (order: ImagingOrder) => {
    const value = reports[order.id] ?? { report: '', impression: '' };
    if (!value.report.trim() && !value.impression.trim()) return;
    const { error } = await supabase.from('imaging_orders').update({ report: value.report, impression: value.impression, status: 'completed' }).eq('id', order.id);
    if (error) return toast({ title: 'Report failed', description: error.message, variant: 'destructive' });
    if (order.service_order_id) { try { await completeServiceOrder(order.service_order_id); } catch { /* clinical report remains saved; queue completion can be retried */ } }
    toast({ title: 'Imaging report saved' }); void load();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><ImageIcon className="w-6 h-6 text-primary" /> Imaging</h1><p className="text-muted-foreground">Request, release, perform and report diagnostic imaging through the central service queue.</p></div>
      <div className="rounded-xl border border-primary/20 bg-primary/5 p-3 flex items-start gap-2 text-sm"><CreditCard className="w-4 h-4 text-primary mt-0.5 shrink-0" /><p className="text-muted-foreground">Chargeable imaging is held until Accounts releases payment or an authorised override is recorded.</p></div>

      <form onSubmit={createOrder} className="card-medical p-5 space-y-3">
        <h2 className="font-semibold">New imaging request</h2>
        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
          <select value={patientId} onChange={e => setPatientId(e.target.value)} className="input-medical" required><option value="">Select patient…</option>{patients.map(p => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}</select>
          <select value={modality} onChange={e => setModality(e.target.value)} className="input-medical"><option>X-Ray</option><option>Ultrasound</option><option>CT</option><option>MRI</option><option>Mammography</option><option>Fluoroscopy</option></select>
          <input value={studyName} onChange={e => setStudyName(e.target.value)} placeholder="Study name" className="input-medical" required />
          <input value={bodySite} onChange={e => setBodySite(e.target.value)} placeholder="Body site" className="input-medical" />
          <select value={priority} onChange={e => setPriority(e.target.value)} className="input-medical"><option value="routine">Routine</option><option value="urgent">Urgent</option><option value="stat">STAT</option></select>
          <input type="number" min={0} step="0.01" value={amount || ''} onChange={e => setAmount(Number(e.target.value))} placeholder="Charge (GHS)" className="input-medical" />
        </div>
        <textarea value={indication} onChange={e => setIndication(e.target.value)} placeholder="Clinical indication" className="input-medical w-full" rows={3} />
        <button className="btn-primary inline-flex items-center gap-2"><Plus className="w-4 h-4" /> {amount > 0 ? 'Request payment approval' : 'Create imaging request'}</button>
      </form>

      <div className="card-medical p-5"><h2 className="font-semibold mb-3">Imaging queue</h2><div className="space-y-3">{orders.map(order => { const value = reports[order.id] ?? { report: order.report ?? '', impression: order.impression ?? '' }; return <div key={order.id} className="rounded-xl border border-border p-4 space-y-3"><div className="flex flex-wrap justify-between gap-3"><div><p className="font-medium">{order.study_name} · {order.modality}</p><p className="text-xs text-muted-foreground">{order.patients?.first_name} {order.patients?.last_name} · {order.body_site || '—'} · {order.priority}</p></div><span className="text-xs font-semibold px-2 py-1 rounded-full bg-muted">{order.status}</span></div>{order.status === 'released' && <button onClick={() => void start(order)} className="btn-primary text-xs">Start imaging</button>}{['in_progress','completed'].includes(order.status) && <div className="space-y-2"><textarea value={value.report} onChange={e => setReports({ ...reports, [order.id]: { ...value, report: e.target.value } })} placeholder="Radiology report" rows={3} className="input-medical w-full" /><textarea value={value.impression} onChange={e => setReports({ ...reports, [order.id]: { ...value, impression: e.target.value } })} placeholder="Impression" rows={2} className="input-medical w-full" />{order.status !== 'completed' && <button onClick={() => void saveReport(order)} className="btn-primary inline-flex items-center gap-2 text-xs"><CheckCircle2 className="w-4 h-4" /> Save report & complete</button>}</div>}</div>; })}{orders.length === 0 && <p className="text-sm text-muted-foreground">No imaging orders yet.</p>}</div></div>
    </div>
  );
}
