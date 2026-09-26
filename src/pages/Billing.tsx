import { useCallback, useEffect, useMemo, useState } from 'react';
import { CalendarDays, CheckCircle2, CreditCard, Loader2, Plus, RefreshCw, ShieldCheck, Wallet, ReceiptText, Activity, CircleDollarSign } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { subscribeMasterDataChanged } from '@/lib/masterDataEvents';
import CatalogueCreateModal from '@/components/catalogue/CatalogueCreateModal';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string; membership_type?: string; membership_expires_at?: string | null; insurance_provider: string | null; insurance_number: string | null }
interface BillableItem { invoice_id: string; invoice_item_id: string; source_type: string | null; source_id: string | null; description: string; category: string | null; department: string | null; quantity: number; unit_price: number; amount: number; paid_amount: number; outstanding_amount: number; service_order_id: string | null; service_order_status: string | null }
interface Tariff { id: string; service_code: string; service_name: string; department: string; unit: string; amount: number; active: boolean }
const db = supabase as any;
const money = (v: number) => `₵${Number(v || 0).toFixed(2)}`;
const categoryLabel: Record<string, string> = { consultation: 'Consultation', lab: 'Laboratory', imaging: 'Diagnostic imaging', pharmacy: 'Pharmacy / drugs', ward: 'Accommodation', feeding: 'Feeding', procedure: 'Medical service' };
const activeStatuses = new Set(['released', 'in_progress', 'completed']);

export default function Billing() {
  const { user } = useAuth();
  const canPrepareBill = user?.roles?.some((role) => ['admin', 'accountant', 'front_desk'].includes(role)) ?? false;
  const [patients, setPatients] = useState<Patient[]>([]);
  const [tariffs, setTariffs] = useState<Tariff[]>([]);
  const [patientId, setPatientId] = useState('');
  const [from, setFrom] = useState(() => new Date().toISOString().slice(0, 10));
  const [to, setTo] = useState(() => new Date().toISOString().slice(0, 10));
  const [items, setItems] = useState<BillableItem[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [invoiceId, setInvoiceId] = useState('');
  const [loading, setLoading] = useState(false);
  const [paying, setPaying] = useState(false);
  const [method, setMethod] = useState('cash');
  const [reference, setReference] = useState('');
  const [walkInCode, setWalkInCode] = useState('');
  const [walkInSearch, setWalkInSearch] = useState('');
  const [createServiceName, setCreateServiceName] = useState('');
  const [walkInQty, setWalkInQty] = useState(1);
  const selectedPatient = patients.find((p) => p.id === patientId);
  const canCreateServices = user?.roles.some((role) => role === 'admin' || role === 'it_admin') || user?.permissions.includes('create_services');
  const filteredTariffs = useMemo(() => tariffs.filter((t) => `${t.service_code} ${t.service_name} ${t.department}`.toLowerCase().includes(walkInSearch.toLowerCase())), [tariffs, walkInSearch]);

  const loadPatients = useCallback(async () => {
    const { data, error } = await supabase.from('patients').select('id,first_name,last_name,patient_code,membership_type,membership_expires_at,insurance_provider,insurance_number').order('created_at', { ascending: false }).limit(1000);
    if (error) toast.error(error.message); else setPatients((data ?? []) as Patient[]);
    const { data: t } = await supabase.from('service_tariffs').select('id,service_code,service_name,department,unit,amount,active').eq('active', true).order('service_name');
    setTariffs((t ?? []) as Tariff[]);
  }, []);

  const loadBillable = useCallback(async () => {
    if (!patientId || !canPrepareBill) { setItems([]); setSelected([]); setInvoiceId(''); return; }
    setLoading(true);
    const { data, error } = await db.rpc('prepare_patient_billable_items', { _patient_id: patientId, _from: `${from}T00:00:00+00:00`, _to: `${to}T23:59:59+00:00` });
    setLoading(false);
    if (error) { playWorkflowSound('critical'); return toast.error(`Unable to prepare patient bill: ${error.message}`); }
    const rows = (data ?? []) as BillableItem[];
    setItems(rows); setInvoiceId(rows[0]?.invoice_id ?? ''); setSelected([]);
  }, [canPrepareBill, from, patientId, to]);

  useEffect(() => { void loadPatients(); return subscribeMasterDataChanged(['tariffs','services','patients'], () => void loadPatients()); }, [loadPatients]);
  useEffect(() => { void loadBillable(); }, [loadBillable]);
  useEffect(() => {
    if (!patientId || !canPrepareBill) return;
    const channel = supabase.channel(`billing-live-${patientId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders', filter: `patient_id=eq.${patientId}` }, () => void loadBillable())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'invoices', filter: `patient_id=eq.${patientId}` }, () => void loadBillable())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [canPrepareBill, loadBillable, patientId]);

  const totals = useMemo(() => items.reduce((acc, item) => {
    acc.gross += Number(item.amount || 0); acc.paid += Number(item.paid_amount || 0); acc.outstanding += Number(item.outstanding_amount || 0);
    if (activeStatuses.has(item.service_order_status ?? '')) acc.released += 1;
    if (item.service_order_status === 'completed') acc.completed += 1;
    return acc;
  }, { gross: 0, paid: 0, outstanding: 0, released: 0, completed: 0 }), [items]);
  const finalStatus = totals.outstanding <= 0 && items.length > 0 ? 'Fully settled' : totals.paid > 0 ? 'Partially settled' : 'Open account';
  const selectedTotal = useMemo(() => items.filter((i) => selected.includes(i.invoice_item_id)).reduce((s, i) => s + Number(i.outstanding_amount), 0), [items, selected]);
  const selectable = items.filter((i) => Number(i.outstanding_amount) > 0 && !activeStatuses.has(i.service_order_status ?? ''));
  const toggle = (id: string) => setSelected((v) => v.includes(id) ? v.filter((x) => x !== id) : [...v, id]);
  const selectAll = () => setSelected(selected.length === selectable.length ? [] : selectable.map((i) => i.invoice_item_id));

  const addWalkIn = async () => {
    if (!patientId || !walkInCode) return toast.error('Select the patient and service.');
    const { error } = await db.rpc('create_walk_in_billable_service', { _patient_id: patientId, _service_code: walkInCode, _quantity: walkInQty, _notes: 'Billing office walk-in service' });
    if (error) { playWorkflowSound('critical'); return toast.error(error.message); }
    playWorkflowSound('success'); toast.success('Walk-in service added to the patient account.'); setWalkInCode(''); setWalkInSearch(''); setWalkInQty(1); await loadBillable();
  };

  const paySelected = async () => {
    if (!invoiceId || !selected.length) return toast.error('Select at least one unpaid service.');
    if (selectedTotal <= 0) return toast.error('Selected services have no outstanding balance.');
    setPaying(true);
    if (method === 'insurance') {
      if (!selectedPatient?.insurance_provider || !selectedPatient.insurance_number) { setPaying(false); return toast.error('The patient must have an insurer and member number before an insurance claim can be created.'); }
      const { error } = await db.rpc('create_insurance_claim_draft', { _patient_id: patientId, _payer_name: selectedPatient.insurance_provider, _member_number: selectedPatient.insurance_number, _amount_claimed: selectedTotal, _invoice_id: invoiceId });
      setPaying(false); if (error) { playWorkflowSound('critical'); return toast.error(`Unable to create insurance claim: ${error.message}`); }
      playWorkflowSound('success'); toast.success(`${money(selectedTotal)} submitted to the insurance claims queue. No cash payment was recorded.`); setSelected([]); setReference(''); return;
    }
    const { error } = await db.rpc('pay_selected_invoice_items', { _invoice_id: invoiceId, _item_ids: selected, _method: method, _reference: reference || null });
    setPaying(false);
    if (error) { playWorkflowSound('critical'); return toast.error(error.message); }
    playWorkflowSound('success'); toast.success(`${money(selectedTotal)} received. Selected services released to their departments.`); setSelected([]); setReference(''); await loadBillable();
  };

  const counters = [
    { label: 'Final bill', value: money(totals.gross), icon: ReceiptText, tone: 'text-primary', surface: 'bg-primary/5' },
    { label: 'Paid to date', value: money(totals.paid), icon: CircleDollarSign, tone: 'text-success', surface: 'bg-success/5' },
    { label: 'Outstanding', value: money(totals.outstanding), icon: Wallet, tone: totals.outstanding > 0 ? 'text-warning' : 'text-success', surface: 'bg-warning/5' },
    { label: 'Released services', value: String(totals.released), icon: Activity, tone: 'text-info', surface: 'bg-info/5' },
  ];

  return (
    <OperationalWorklistShell
      icon={CreditCard}
      eyebrow="Business & Reporting · Billing"
      title="Billing & Patient Account"
      description="Reconcile one patient account across consultations, diagnostics, medicines, procedures, accommodation and other recorded services."
      actions={(
        <button type="button" onClick={() => { playWorkflowSound('info'); void loadBillable(); }} className="btn-secondary inline-flex items-center gap-2" disabled={!patientId || loading} aria-label="Refresh patient billing account">
          <RefreshCw className="w-4 h-4" aria-hidden="true" /> {loading ? 'Refreshing…' : 'Refresh account'}
        </button>
      )}
      counters={patientId ? counters.map(({ label, value, tone, surface }) => ({ label, value, tone, surface })) : []}
      beforeList={(
        <>
          <section className="card-medical p-5 space-y-4" aria-label="Billing patient and date selection">
            <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_170px_170px_auto] items-end">
              <label className="text-sm space-y-1"><span className="font-medium">Patient</span><select value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full" aria-label="Select patient"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}</select></label>
              <label className="text-sm space-y-1"><span>From</span><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="input-medical w-full" aria-label="Billing period start date" /></label>
              <label className="text-sm space-y-1"><span>To</span><input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="input-medical w-full" aria-label="Billing period end date" /></label>
              <button type="button" onClick={() => void loadBillable()} className="btn-primary inline-flex justify-center gap-2" disabled={!patientId || loading}>{loading ? <Loader2 className="w-4 h-4 animate-spin" aria-hidden="true" /> : <CalendarDays className="w-4 h-4" aria-hidden="true" />} Prepare bill</button>
            </div>
            {selectedPatient && <div className="flex flex-wrap gap-2 text-xs"><span className="rounded-full bg-muted px-3 py-1">{selectedPatient.first_name} {selectedPatient.last_name}</span><span className="rounded-full bg-muted px-3 py-1">{selectedPatient.membership_type === 'temporary' ? 'Temporary visitor' : 'Registered patient'}</span>{selectedPatient.membership_expires_at && <span className="rounded-full bg-warning/10 text-warning px-3 py-1">Expires {new Date(selectedPatient.membership_expires_at).toLocaleDateString()}</span>}{selectedPatient.insurance_provider && <span className="rounded-full bg-primary/10 text-primary px-3 py-1 inline-flex items-center gap-1"><ShieldCheck className="w-3 h-3" aria-hidden="true" />{selectedPatient.insurance_provider}</span>}<span className={`rounded-full px-3 py-1 ${finalStatus === 'Fully settled' ? 'bg-success/10 text-success' : 'bg-warning/10 text-warning'}`}>Account: {finalStatus}</span></div>}
          </section>
          {patientId && <section className="card-medical p-5"><div className="flex items-center gap-2 mb-3"><Plus className="w-4 h-4 text-primary" /><div><h2 className="font-semibold">Walk-in service</h2><p className="text-xs text-muted-foreground">Add an additional service to the same patient account.</p></div></div><div className="grid md:grid-cols-[1fr_120px_auto] gap-2 items-end"><input value={walkInSearch} onChange={(e) => setWalkInSearch(e.target.value)} className="input-medical" placeholder="Search service or service code" /><select value={walkInCode} onChange={(e) => setWalkInCode(e.target.value)} className="input-medical"><option value="">Select service tariff…</option>{filteredTariffs.map((t) => <option key={t.id} value={t.service_code}>{t.service_name} · {t.department} · {money(Number(t.amount))}/{t.unit}</option>)}</select>{canCreateServices && walkInSearch.trim() && filteredTariffs.length === 0 && <button type="button" onClick={() => setCreateServiceName(walkInSearch.trim())} className="btn-secondary">Add {walkInSearch.trim()}</button>}<input type="number" min={1} value={walkInQty} onChange={(e) => setWalkInQty(Number(e.target.value))} className="input-medical" /><button onClick={() => void addWalkIn()} className="btn-primary">Add to bill</button></div></section>}
        </>
      )}
      listTitle="Patient billing ledger"
      listDescription={patientId ? "Select unpaid services to record payment or create an insurance claim; released services remain visible for reconciliation." : "Select a patient and billing period to prepare the account ledger."}
      listMeta={patientId ? `${items.length} service item${items.length === 1 ? '' : 's'} · ${money(totals.outstanding)} outstanding` : undefined}
      loading={loading}
      empty={!patientId}
      emptyIcon={ReceiptText}
      emptyTitle="Select a patient to prepare the account"
      emptyDescription="Choose a patient and date range above to compute recorded billable services."
    >
        <section className="card-medical p-5 space-y-4"><div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_170px_170px_auto] items-end"><label className="text-sm space-y-1"><span className="font-medium">Patient</span><select value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}</select></label><label className="text-sm space-y-1"><span>From</span><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="input-medical w-full" /></label><label className="text-sm space-y-1"><span>To</span><input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="input-medical w-full" /></label><button onClick={() => void loadBillable()} className="btn-primary inline-flex justify-center gap-2" disabled={!patientId || loading}>{loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <CalendarDays className="w-4 h-4" />}Prepare bill</button></div>{selectedPatient && <div className="flex flex-wrap gap-2 text-xs"><span className="rounded-full bg-muted px-3 py-1">{selectedPatient.first_name} {selectedPatient.last_name}</span><span className="rounded-full bg-muted px-3 py-1">{selectedPatient.membership_type === 'temporary' ? 'Temporary visitor' : 'Registered patient'}</span>{selectedPatient.membership_expires_at && <span className="rounded-full bg-warning/10 text-warning px-3 py-1">Expires {new Date(selectedPatient.membership_expires_at).toLocaleDateString()}</span>}{selectedPatient.insurance_provider && <span className="rounded-full bg-primary/10 text-primary px-3 py-1 inline-flex items-center gap-1"><ShieldCheck className="w-3 h-3" />{selectedPatient.insurance_provider}</span>}<span className={`rounded-full px-3 py-1 ${finalStatus === 'Fully settled' ? 'bg-success/10 text-success' : 'bg-warning/10 text-warning'}`}>Account: {finalStatus}</span></div>}</section>

        {!patientId ? <div className="card-medical p-10 text-center text-muted-foreground">Select a patient to compute the current account and reconcile services rendered during the selected period.</div> : <>
      <section className="card-medical p-5"><div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between mb-4"><div><h2 className="font-semibold">Final bill ledger</h2><p className="text-xs text-muted-foreground">The account is recomputed from recorded clinical services. Paid history remains visible and each source is protected against duplicate billing lines.</p></div><button onClick={selectAll} className="btn-secondary text-xs">{selected.length === selectable.length && selectable.length ? 'Clear selection' : 'Select all unpaid'}</button></div><div className="space-y-2">{items.map((item) => { const due = Number(item.outstanding_amount); const checked = selected.includes(item.invoice_item_id); const released = activeStatuses.has(item.service_order_status ?? ''); return <label key={item.invoice_item_id} className={`flex items-center gap-3 rounded-xl border p-3 ${due <= 0 || released ? 'opacity-60' : 'cursor-pointer hover:bg-muted/30'} ${checked ? 'border-primary bg-primary/5' : 'border-border'}`}><input type="checkbox" checked={checked} disabled={due <= 0 || released} onChange={() => toggle(item.invoice_item_id)} /><div className="min-w-0 flex-1"><div className="flex flex-wrap gap-2"><span className="font-medium text-sm">{item.description}</span><span className="text-[10px] rounded-full bg-muted px-2 py-0.5">{categoryLabel[item.category ?? ''] ?? item.category ?? 'Service'}</span>{released && <span className="text-[10px] rounded-full bg-success/10 text-success px-2 py-0.5">Released</span>}</div><p className="text-xs text-muted-foreground">{item.department ?? 'clinical service'} · Qty {item.quantity} · {money(Number(item.unit_price))} each</p></div><div className="text-right shrink-0"><p className="font-semibold">{money(due)}</p>{due <= 0 && <p className="text-[10px] text-success inline-flex items-center gap-1"><CheckCircle2 className="w-3 h-3" />Paid</p>}</div></label> })}{!items.length && <p className="text-sm text-muted-foreground py-6 text-center">No billable items were found for this period.</p>}</div></section>
      <section className="card-medical p-5 grid gap-4 lg:grid-cols-[1fr_420px] items-end"><div><p className="text-sm text-muted-foreground">Selected services</p><p className="text-3xl font-bold">{money(selectedTotal)}</p><p className="text-xs text-muted-foreground mt-1">{method === 'insurance' ? 'Insurance selection creates a claim draft and does not record a cash payment.' : 'Payment releases each selected item to the affected department.'}</p></div><div className="grid grid-cols-2 gap-2"><select value={method} onChange={(e) => setMethod(e.target.value)} className="input-medical"><option value="cash">Cash</option><option value="card">Card</option><option value="mobile_money">Mobile Money</option><option value="insurance">Insurance claim</option><option value="advance">Advance</option></select><input value={reference} onChange={(e) => setReference(e.target.value)} className="input-medical" placeholder={method === 'insurance' ? 'Optional claim reference' : 'Payment reference'} /><button onClick={() => void paySelected()} disabled={paying || !selected.length} className="btn-primary col-span-2 inline-flex justify-center gap-2"><Wallet className="w-4 h-4" />{paying ? (method === 'insurance' ? 'Creating claim…' : 'Recording payment…') : method === 'insurance' ? `Create claim · ${money(selectedTotal)}` : `Pay selected · ${money(selectedTotal)}`}</button></div></section>
    </>}
    <p className="text-xs text-muted-foreground">Billing operator: {user?.email ?? 'authenticated user'} · Invoice: {invoiceId || 'not prepared'}</p>
    {createServiceName && <CatalogueCreateModal kind="service" initialName={createServiceName} userRoles={user?.roles ?? []} userPermissions={user?.permissions ?? []} userDepartment={user?.department} onCreated={() => { void loadPatients(); setWalkInSearch(createServiceName); }} onClose={() => setCreateServiceName('')} />}
    </OperationalWorklistShell>
  );
}
