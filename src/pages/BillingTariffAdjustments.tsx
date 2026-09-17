import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CheckCircle2, CircleDollarSign, RefreshCw, ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { toast } from 'sonner';

type MissingTariff = {
  invoice_item_id: string;
  invoice_id: string;
  patient_id: string;
  description: string;
  department: string | null;
  service_code: string | null;
  quantity: number;
  unit_price: number;
  amount: number;
  service_order_id: string | null;
  service_order_status: string | null;
  created_at: string;
};
type Patient = { id: string; first_name: string; last_name: string; patient_code: string };
const db = supabase as any;
const money = (value: number) => `₵${Number(value || 0).toFixed(2)}`;

export default function BillingTariffAdjustments() {
  const { user } = useAuth();
  const [items, setItems] = useState<MissingTariff[]>([]);
  const [patients, setPatients] = useState<Patient[]>([]);
  const [patientId, setPatientId] = useState('');
  const [prices, setPrices] = useState<Record<string, string>>({});
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const isAuthorized = user?.role === 'admin' || user?.role === 'accountant';

  const load = useCallback(async () => {
    if (!isAuthorized) return;
    setLoading(true);
    const [{ data: rows, error }, { data: patientRows }] = await Promise.all([
      db.rpc('get_missing_billing_tariffs', { _patient_id: patientId || null }),
      supabase.from('patients').select('id,first_name,last_name,patient_code').order('first_name').limit(1000),
    ]);
    setLoading(false);
    if (error) {
      playWorkflowSound('critical');
      toast.error(`Unable to load missing tariffs: ${error.message}`);
      return;
    }
    setItems((rows ?? []) as MissingTariff[]);
    setPatients((patientRows ?? []) as Patient[]);
  }, [isAuthorized, patientId]);

  useEffect(() => { void load(); }, [load]);

  useEffect(() => {
    if (!isAuthorized) return;
    const channel = supabase.channel('billing-tariff-adjustments-live')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'invoice_items' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders' }, () => void load())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [isAuthorized, load]);

  const patientMap = useMemo(() => Object.fromEntries(patients.map((p) => [p.id, p])), [patients]);
  const missingCount = items.length;

  const adjust = async (item: MissingTariff) => {
    const rawPrice = prices[item.invoice_item_id] ?? '';
    const adjustedPrice = Number(rawPrice);
    const reason = (reasons[item.invoice_item_id] ?? '').trim();
    if (!Number.isFinite(adjustedPrice) || adjustedPrice < 0) return toast.error('Enter a valid tariff amount of zero or greater.');
    if (reason.length < 5) return toast.error('Provide a clear reason for the tariff adjustment.');
    setSaving(item.invoice_item_id);
    const { error } = await db.rpc('adjust_invoice_item_tariff', {
      _invoice_item_id: item.invoice_item_id,
      _adjusted_unit_price: adjustedPrice,
      _reason: reason,
      _adjustment_type: 'missing_tariff',
    });
    setSaving(null);
    if (error) {
      playWorkflowSound('critical');
      toast.error(`Tariff adjustment failed: ${error.message}`);
      return;
    }
    playWorkflowSound('success');
    toast.success(`${item.description} tariff adjusted to ${money(adjustedPrice)} per ${item.quantity > 1 ? 'unit' : 'service'}.`);
    setPrices((current) => { const next = { ...current }; delete next[item.invoice_item_id]; return next; });
    setReasons((current) => { const next = { ...current }; delete next[item.invoice_item_id]; return next; });
    await load();
  };

  if (!user) return null;
  if (!isAuthorized) return <div className="card-medical p-8 text-center"><ShieldCheck className="mx-auto h-8 w-8 text-warning" /><h1 className="mt-3 text-xl font-semibold">Billing tariff adjustments</h1><p className="mt-2 text-sm text-muted-foreground">Only Accounts or administrators can adjust a missing tariff. Clinical users can continue recording services without changing billing values.</p></div>;

  return <div className="space-y-6 animate-fade-in">
    <header className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><CircleDollarSign className="w-6 h-6 text-primary" />Billing Tariff Adjustments</h1><p className="text-muted-foreground">Resolve services that reached billing without a configured tariff before payment or departmental release.</p></div>
      <button onClick={() => { playWorkflowSound('info'); void load(); }} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="w-4 h-4" />{loading ? 'Refreshing...' : 'Refresh worklist'}</button>
    </header>

    <section className="grid grid-cols-2 lg:grid-cols-3 gap-3">
      <div className="card-medical bg-warning/5 p-4"><p className="text-xs text-muted-foreground">Missing tariffs</p><p className={`text-2xl font-bold ${missingCount ? 'text-warning animate-pulse' : 'text-success'}`}>{missingCount}</p></div>
      <div className="card-medical bg-info/5 p-4"><p className="text-xs text-muted-foreground">Awaiting billing action</p><p className="text-2xl font-bold text-info">{items.filter((i) => i.service_order_status === 'pending_payment_approval').length}</p></div>
      <div className="card-medical bg-primary/5 p-4 col-span-2 lg:col-span-1"><p className="text-xs text-muted-foreground">Control</p><p className="text-sm font-semibold">Every adjustment is reasoned and audited</p></div>
    </section>

    <section className="card-medical p-5"><label className="text-sm space-y-1 block max-w-xl"><span className="font-medium">Filter by patient</span><select value={patientId} onChange={(event) => setPatientId(event.target.value)} className="input-medical w-full"><option value="">All patients</option>{patients.map((patient) => <option key={patient.id} value={patient.id}>{patient.first_name} {patient.last_name} · {patient.patient_code}</option>)}</select></label></section>

    <section className="space-y-3">
      {items.map((item) => {
        const patient = patientMap[item.patient_id];
        const suggested = prices[item.invoice_item_id] ?? '';
        return <article key={item.invoice_item_id} className="card-medical border-warning/30 bg-warning/5 p-5 space-y-4">
          <div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex flex-wrap items-center gap-2"><h2 className="font-semibold">{item.description}</h2><span className="rounded-full bg-warning/15 px-2 py-1 text-xs text-warning inline-flex items-center gap-1"><AlertTriangle className="h-3 w-3" />Missing tariff</span></div><p className="text-sm text-muted-foreground">{patient ? `${patient.first_name} ${patient.last_name} · ${patient.patient_code}` : 'Patient'} · {item.department ?? 'Department not recorded'} · {item.service_code ?? 'No service code'}</p><p className="text-xs text-muted-foreground">Invoice {item.invoice_id.slice(0, 8)} · Qty {item.quantity} · Current amount {money(item.amount)} · {item.service_order_status ?? 'No service order'}</p></div><div className="text-right"><p className="text-xs text-muted-foreground">Current tariff</p><p className="text-xl font-bold text-warning">{money(item.unit_price)}</p></div></div>
          <div className="grid gap-3 lg:grid-cols-[220px_1fr_auto] items-end"><label className="text-sm space-y-1"><span>Adjusted unit tariff (GHS)</span><input type="number" min="0" step="0.01" value={suggested} onChange={(event) => setPrices((current) => ({ ...current, [item.invoice_item_id]: event.target.value }))} className="input-medical w-full" placeholder="0.00" /></label><label className="text-sm space-y-1"><span>Reason / billing basis</span><input value={reasons[item.invoice_item_id] ?? ''} onChange={(event) => setReasons((current) => ({ ...current, [item.invoice_item_id]: event.target.value }))} className="input-medical w-full" placeholder="e.g. Approved facility tariff schedule, effective date..." /></label><button type="button" disabled={saving === item.invoice_item_id} onClick={() => void adjust(item)} className="btn-primary inline-flex items-center justify-center gap-2 disabled:opacity-60">{saving === item.invoice_item_id ? 'Applying...' : <><CheckCircle2 className="h-4 w-4" />Apply tariff</>}</button></div>
          <p className="text-xs text-muted-foreground">The adjustment changes this unpaid invoice item. If its service order is still awaiting payment approval, the service-order amount is synchronized so Accounts and the receiving department use the same amount. Paid items cannot be changed.</p>
        </article>;
      })}
      {!items.length && <div className="card-medical p-10 text-center"><CheckCircle2 className="mx-auto h-8 w-8 text-success" /><p className="mt-3 font-semibold">No missing tariffs in the billing worklist.</p><p className="text-sm text-muted-foreground mt-1">New zero-tariff billable services will appear here for controlled Accounts action.</p></div>}
    </section>
  </div>;
}
