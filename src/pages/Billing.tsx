import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { CalendarDays, CheckCircle2, CreditCard, FileText, Loader2, Plus, Printer, RefreshCw, ShieldCheck, Wallet, ReceiptText, Activity, CircleDollarSign } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { subscribeMasterDataChanged } from '@/lib/masterDataEvents';
import CatalogueCreateModal from '@/components/catalogue/CatalogueCreateModal';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string; membership_type?: string; membership_expires_at?: string | null; insurance_provider: string | null; insurance_number: string | null; insurance_expiry?: string | null }
interface BillableItem { invoice_id: string; invoice_item_id: string; source_type: string | null; source_id: string | null; description: string; category: string | null; department: string | null; quantity: number; unit_price: number; amount: number; paid_amount: number; outstanding_amount: number; service_order_id: string | null; service_order_status: string | null }
interface BillingWindow { invoice_id: string; account_id: string; records_folder_id: string; patient_name: string; patient_type: 'Insured' | 'Cash / Non-Insured'; insurance_name: string | null; encounter_id: string | null; date_time: string; total_amount: number; insurance_total: number; top_up_total: number; credit_balance: number; amount_due: number; items: Array<BillableItem & { charge: number; insurance_charge: number; top_up: number; billed_at: string | null }> }
interface Tariff { id: string; service_code: string; service_name: string; department: string; unit: string; amount: number; active: boolean }
const db = supabase as any;
const money = (v: number) => `₵${Number(v || 0).toFixed(2)}`;
const smallNumberWords = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const tensWords = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
const integerToWords = (value: number): string => {
  const n = Math.floor(Math.max(0, value));
  if (n < 20) return smallNumberWords[n];
  if (n < 100) return tensWords[Math.floor(n / 10)] + (n % 10 ? '-' + smallNumberWords[n % 10] : '');
  if (n < 1000) return smallNumberWords[Math.floor(n / 100)] + ' hundred' + (n % 100 ? ' and ' + integerToWords(n % 100) : '');
  if (n < 1000000) return integerToWords(Math.floor(n / 1000)) + ' thousand' + (n % 1000 ? ' ' + integerToWords(n % 1000) : '');
  if (n < 1000000000) return integerToWords(Math.floor(n / 1000000)) + ' million' + (n % 1000000 ? ' ' + integerToWords(n % 1000000) : '');
  return integerToWords(Math.floor(n / 1000000000)) + ' billion' + (n % 1000000000 ? ' ' + integerToWords(n % 1000000000) : '');
};
const amountInWords = (value: number): string => {
  const cents = Math.round(Math.max(0, Number(value || 0)) * 100);
  const major = Math.floor(cents / 100);
  const minor = cents % 100;
  const cedi = major === 1 ? 'cedi' : 'cedis';
  return integerToWords(major) + ' Ghana ' + cedi + ' ' + integerToWords(minor) + ' pesewas';
};
const categoryLabel: Record<string, string> = { consultation: 'Consultation', lab: 'Laboratory', imaging: 'Diagnostic imaging', pharmacy: 'Pharmacy / drugs', ward: 'Accommodation', feeding: 'Feeding', procedure: 'Medical service' };
const activeStatuses = new Set(['released', 'in_progress', 'completed']);

export default function Billing() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const canViewClaims = user?.roles?.some((role) => role === 'admin' || role === 'accountant') ?? false;
  const canPrepareBill = user?.roles?.some((role) => ['admin', 'accountant', 'front_desk'].includes(role)) ?? false;
  const [patients, setPatients] = useState<Patient[]>([]);
  const [tariffs, setTariffs] = useState<Tariff[]>([]);
  const [patientId, setPatientId] = useState('');
  const [from, setFrom] = useState(() => new Date().toISOString().slice(0, 10));
  const [items, setItems] = useState<BillableItem[]>([]);
  const [billingWindow, setBillingWindow] = useState<BillingWindow | null>(null);
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
    if (!patientId || !canPrepareBill) {
      setItems([]);
      setBillingWindow(null);
      setSelected([]);
      setInvoiceId('');
      return;
    }
    setLoading(true);
    const { data, error } = await db.rpc('get_billing_window', {
      _patient_id: patientId,
      _at: from + 'T23:59:59.999Z',
    });
    setLoading(false);
    if (error) {
      setBillingWindow(null);
      setItems([]);
      setSelected([]);
      playWorkflowSound('critical');
      toast.error('Unable to prepare billing window: ' + error.message);
      return;
    }
    const prepared = (data ?? null) as BillingWindow | null;
    setBillingWindow(prepared);
    setItems((prepared?.items ?? []) as BillableItem[]);
    setInvoiceId(prepared?.invoice_id ?? '');
    setSelected([]);
  }, [canPrepareBill, from, patientId]);

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
    acc.gross += Number((billingWindow?.patient_type === 'Insured' ? item.amount : item.amount) || 0);
    acc.insurance += Number((item as any).insurance_charge || 0);
    acc.topUp += Number((item as any).top_up || item.outstanding_amount || 0);
    acc.paid += Number(item.paid_amount || 0);
    acc.outstanding += Number(item.outstanding_amount || 0);
    if (activeStatuses.has(item.service_order_status ?? '')) acc.released += 1;
    return acc;
  }, { gross: 0, insurance: 0, topUp: 0, paid: 0, outstanding: 0, released: 0 }), [billingWindow, items]);
  const finalStatus = totals.outstanding <= 0 && items.length > 0 ? 'Fully settled' : totals.paid > 0 ? 'Partially settled' : 'Open account';
  const selectedTotal = useMemo(() => items.filter((i) => selected.includes(i.invoice_item_id)).reduce((s, i) => s + Number((billingWindow?.patient_type === 'Insured' ? (i as any).top_up : i.outstanding_amount) || 0), 0), [billingWindow, items, selected]);
  const selectable = items.filter((i) => Number(i.outstanding_amount) > 0);
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
      const insuranceTotal = items.filter((item) => selected.includes(item.invoice_item_id)).reduce((sum, item) => sum + Number((item as any).insurance_charge || 0), 0);
      const { error } = await db.rpc('create_insurance_claim_draft', { _patient_id: patientId, _payer_name: billingWindow?.insurance_name ?? selectedPatient.insurance_provider, _member_number: selectedPatient.insurance_number, _amount_claimed: insuranceTotal, _invoice_id: invoiceId });
      setPaying(false); if (error) { playWorkflowSound('critical'); return toast.error('Unable to create insurance claim: ' + error.message); }
      const { error: billedError } = await db.rpc('mark_billing_items_billed', { _invoice_id: invoiceId, _item_ids: selected });
      if (billedError) { playWorkflowSound('critical'); return toast.error('Claim created, but billing finalization failed: ' + billedError.message); }
      playWorkflowSound('success'); toast.success(money(insuranceTotal) + ' submitted to the insurance claims queue. No cash payment was recorded.'); setSelected([]); setReference(''); await loadBillable(); return;
    }
    const { error } = await db.rpc('pay_selected_invoice_items', { _invoice_id: invoiceId, _item_ids: selected, _method: method, _reference: reference || null });
    setPaying(false);
    if (error) { playWorkflowSound('critical'); return toast.error(error.message); }
    playWorkflowSound('success'); toast.success(`${money(selectedTotal)} received. Selected services released to their departments.`); setSelected([]); setReference(''); await loadBillable();
  };

  const printReceipt = async () => {
    if (!billingWindow) return;
    const ids = billingWindow.items.map((item) => item.invoice_item_id);
    if (ids.length) {
      const { error } = await db.rpc('mark_billing_items_billed', { _invoice_id: billingWindow.invoice_id, _item_ids: ids });
      if (error) {
        playWorkflowSound('critical');
        toast.error('Receipt finalization failed: ' + error.message);
        return;
      }
    }
    playWorkflowSound('success');
    window.setTimeout(() => window.print(), 50);
  };

  const counters = [
    { label: 'Final bill', value: money(totals.gross), icon: ReceiptText, tone: 'text-primary', surface: 'bg-primary/5' },
    { label: 'Paid to date', value: money(totals.paid), icon: CircleDollarSign, tone: 'text-success', surface: 'bg-success/5' },
    { label: 'Outstanding', value: money(totals.outstanding), icon: Wallet, tone: totals.outstanding > 0 ? 'text-warning' : 'text-success', surface: 'bg-warning/5' },
    { label: 'Released services', value: String(totals.released), icon: Activity, tone: 'text-info', surface: 'bg-info/5' },
  ];

  return (
    <>
      <style>{'@media print { @page { size: A4; margin: 12mm; } body * { visibility: hidden !important; } #billing-print-area, #billing-print-area * { visibility: visible !important; } #billing-print-area { position: absolute; left: 0; top: 0; width: 100%; } .print\\\\:hidden { display: none !important; } }'}</style>
      <OperationalWorklistShell
        icon={CreditCard}
        eyebrow="Business & Reporting · Billing"
        title="Billing"
        description="Encounter-aware billing for Ghana Cedi accounts, with an insured and cash presentation that follows the patient's financial pathway."
        actions={
          <div className="flex flex-wrap gap-2">
            {canViewClaims && <button type="button" onClick={() => navigate('/insurance-claims')} className="btn-secondary inline-flex items-center gap-2"><ShieldCheck className="w-4 h-4" aria-hidden="true" />NHIS / Insurance Claims</button>}
            <button type="button" onClick={() => { playWorkflowSound('info'); void loadBillable(); }} className="btn-secondary inline-flex items-center gap-2" disabled={!patientId || loading}>
              <RefreshCw className="w-4 h-4" aria-hidden="true" />Refresh
            </button>
            {billingWindow && <button type="button" onClick={() => void printReceipt()} className="btn-primary inline-flex items-center gap-2">
              <Printer className="w-4 h-4" aria-hidden="true" />Print receipt
            </button>}
          </div>
        }
        counters={patientId ? counters.map(({ label, value, tone, surface }) => ({ label, value, tone, surface })) : []}
        beforeList={
          <section className="card-medical p-5 space-y-4 print:hidden" aria-labelledby="billing-account-selector">
            <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p className="text-xs uppercase tracking-[0.14em] text-primary font-semibold">Billing window</p>
                <h2 id="billing-account-selector" className="text-lg font-semibold">Select a patient to automatically prepare the account</h2>
                <p className="text-sm text-muted-foreground">The system resolves the active encounter/day and pulls consultations, laboratory, medication, diagnostic and procedure services already recorded for the patient.</p>
              </div>
              <span className="rounded-full bg-primary/5 text-primary px-3 py-1 text-xs font-medium">Server-authoritative</span>
            </div>
            <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_190px_auto] items-end">
              <label className="text-sm space-y-1.5"><span className="font-medium">Patient</span><select aria-label="Select patient account" value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}</select></label>
              <label className="text-sm space-y-1.5"><span className="font-medium">Billing date</span><input aria-label="Billing date" type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="input-medical w-full" /></label>
              <button type="button" onClick={() => void loadBillable()} className="btn-primary inline-flex justify-center gap-2" disabled={!patientId || loading}>{loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <CalendarDays className="w-4 h-4" />}Prepare billing window</button>
            </div>
            {selectedPatient && <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4 text-xs">
              <div className="rounded-xl bg-muted/60 p-3"><span className="text-muted-foreground">Patient Type</span><p className="font-semibold mt-1">{billingWindow?.patient_type ?? 'Resolving…'}</p></div>
              <div className="rounded-xl bg-muted/60 p-3"><span className="text-muted-foreground">Insurance Name</span><p className="font-semibold mt-1">{billingWindow?.insurance_name ?? 'Cash / Non-Insured'}</p></div>
              <div className="rounded-xl bg-muted/60 p-3"><span className="text-muted-foreground">Encounter</span><p className="font-mono font-semibold mt-1 break-all">{billingWindow?.encounter_id ?? 'No active encounter'}</p></div>
              <div className="rounded-xl bg-muted/60 p-3"><span className="text-muted-foreground">Account ID</span><p className="font-semibold mt-1">{billingWindow?.account_id ?? 'Preparing…'}</p></div>
            </div>}
          </section>
        }
        listTitle={billingWindow ? 'Dynamic billing window' : 'Patient account worklist'}
        listDescription={billingWindow ? 'The table changes columns automatically according to the patient type.' : 'Select a patient to open the billing window.'}
        listMeta={billingWindow ? billingWindow.items.length + ' service lines · ' + billingWindow.patient_type : 'Patient selection required'}
        loading={loading}
        empty={Boolean(patientId) && !loading && Boolean(billingWindow) && billingWindow.items.length === 0}
        emptyTitle="No billable services"
        emptyDescription="No billable services were found for this encounter/day. New clinical service orders will appear after the billing window refreshes."
      >
        {billingWindow && <div className="space-y-5">
          <section className="card-medical p-5">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between border-b border-border pb-4">
              <div><p className="text-xs uppercase tracking-[0.14em] text-primary font-semibold">Account</p><h2 className="text-xl font-bold">{billingWindow.patient_name}</h2></div>
              <div className="text-sm sm:text-right"><p><span className="text-muted-foreground">Account ID:</span> <strong>{billingWindow.account_id}</strong></p><p><span className="text-muted-foreground">Records/Folder ID:</span> <strong>{billingWindow.records_folder_id}</strong></p><p><span className="text-muted-foreground">Date and Time:</span> <strong>{new Date(billingWindow.date_time).toLocaleString('en-GH')}</strong></p></div>
            </div>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 pt-4">
              <div><p className="text-xs text-muted-foreground">Patient Type</p><p className="font-semibold">{billingWindow.patient_type}</p></div>
              <div><p className="text-xs text-muted-foreground">Insurance Name</p><p className="font-semibold">{billingWindow.insurance_name ?? 'Cash / Non-Insured'}</p></div>
              <div><p className="text-xs text-muted-foreground">Encounter ID</p><p className="font-mono text-xs font-semibold break-all">{billingWindow.encounter_id ?? '—'}</p></div>
              <div><p className="text-xs text-muted-foreground">Currency</p><p className="font-semibold">Ghana Cedis (GHS)</p></div>
            </div>
          </section>

          <section className="card-medical p-5">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between mb-4"><div><h2 className="font-semibold">Services and charges</h2><p className="text-xs text-muted-foreground">Each line remains linked to its clinical source and is protected from duplicate billing.</p></div><button type="button" onClick={selectAll} className="btn-secondary text-xs">{selected.length === selectable.length && selectable.length ? 'Clear selection' : 'Select all unpaid'}</button></div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[700px] text-sm border-collapse">
                <thead><tr className="bg-muted/70"><th className="border border-border px-3 py-2 text-left w-12">S/n</th><th className="border border-border px-3 py-2 text-left">Description</th><th className="border border-border px-3 py-2 text-right">Charge</th>{billingWindow.patient_type === 'Insured' && <th className="border border-border px-3 py-2 text-right">Insurance Charge</th>}{billingWindow.patient_type === 'Insured' && <th className="border border-border px-3 py-2 text-right">Top up</th>}<th className="border border-border px-3 py-2 text-center">Status</th></tr></thead>
                <tbody>{billingWindow.items.map((item, index) => {
                  const selectedRow = selected.includes(item.invoice_item_id);
                  const due = Number(billingWindow.patient_type === 'Insured' ? item.top_up : item.outstanding_amount);
                  const disabled = Number(item.outstanding_amount) <= 0 || Boolean(item.billed_at);
                  return <tr key={item.invoice_item_id} className={selectedRow ? 'bg-primary/5' : ''}>
                    <td className="border border-border px-3 py-2 align-top"><input type="checkbox" aria-label={'Select ' + item.description} checked={selectedRow} disabled={disabled} onChange={() => toggle(item.invoice_item_id)} /><span className="ml-2">{index + 1}</span></td>
                    <td className="border border-border px-3 py-2"><div className="font-medium">{item.description}</div><div className="text-[11px] text-muted-foreground">{categoryLabel[item.category ?? ''] ?? item.category ?? 'Service'} · {item.department ?? 'clinical'} · Qty {item.quantity}</div></td>
                    <td className="border border-border px-3 py-2 text-right tabular-nums">{money(item.charge ?? item.amount)}</td>
                    {billingWindow.patient_type === 'Insured' && <td className="border border-border px-3 py-2 text-right tabular-nums">{money(item.insurance_charge)}</td>}
                    {billingWindow.patient_type === 'Insured' && <td className="border border-border px-3 py-2 text-right tabular-nums">{money(item.top_up)}</td>}
                    <td className="border border-border px-3 py-2 text-center">{item.billed_at ? <span className="rounded-full bg-success/10 text-success px-2 py-1 text-[11px]">Billed</span> : item.outstanding_amount <= 0 ? <span className="rounded-full bg-success/10 text-success px-2 py-1 text-[11px]">Paid</span> : <span className="rounded-full bg-warning/10 text-warning px-2 py-1 text-[11px]">Due</span>}</td>
                  </tr>;
                })}</tbody>
              </table>
            </div>
          </section>

          <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_400px]">
            <div className="card-medical p-5"><p className="text-xs uppercase tracking-[0.14em] text-primary font-semibold">Financial summary</p><div className="mt-3 space-y-3"><div className="flex justify-between"><span>Total amount</span><strong>{money(billingWindow.total_amount)}</strong></div>{billingWindow.patient_type === 'Insured' && <><div className="flex justify-between"><span>Insurance charge</span><strong>{money(billingWindow.insurance_total)}</strong></div><div className="flex justify-between"><span>Top up</span><strong>{money(billingWindow.top_up_total)}</strong></div></>}<div className="flex justify-between border-t border-border pt-3"><span>Credit balance / Deposit</span><strong>{money(billingWindow.credit_balance)}</strong></div><div className="flex justify-between text-xl font-bold"><span>{billingWindow.amount_due < 0 ? 'Credit' : 'Amount Due'}</span><strong>{money(Math.abs(billingWindow.amount_due))}</strong></div></div></div>
            <div className="card-medical p-5"><p className="text-xs uppercase tracking-[0.14em] text-primary font-semibold">Payment</p><div className="grid gap-2 mt-3"><select value={method} onChange={(e) => setMethod(e.target.value)} className="input-medical" aria-label="Payment method"><option value="cash">Cash</option><option value="card">Card</option><option value="mobile_money">Mobile Money</option><option value="bank_transfer">Bank Transfer</option><option value="cheque">Cheque</option><option value="insurance">Insurance claim</option></select><input value={reference} onChange={(e) => setReference(e.target.value)} className="input-medical" placeholder="Payment / claim reference" aria-label="Payment reference" /><button type="button" onClick={() => void paySelected()} disabled={paying || !selected.length} className="btn-primary">{paying ? 'Processing…' : method === 'insurance' ? 'Submit insurance claim' : 'Record payment'}{selected.length ? ' · ' + money(selectedTotal) : ''}</button></div></div>
          </section>

          <section className="card-medical p-5 bg-muted/30"><div className="flex items-start gap-3"><FileText className="w-5 h-5 text-primary mt-0.5" aria-hidden="true" /><div><h2 className="font-semibold">Amount in words</h2><p className="text-sm mt-1">({billingWindow.amount_due < 0 ? amountInWords(0) : amountInWords(billingWindow.total_amount)}) being payment of medical bill</p></div></div></section>

          <section id="billing-print-area" className="card-medical p-6 print:shadow-none print:border-0 print:p-0">
            <div className="flex flex-col gap-3 sm:flex-row sm:justify-between border-b border-border pb-4"><div><p className="text-xs uppercase tracking-[0.16em] text-primary font-semibold">Harmony Health Hub</p><h2 className="text-2xl font-bold">Medical Billing Receipt</h2></div><div className="text-sm sm:text-right"><p>Account ID: <strong>{billingWindow.account_id}</strong></p><p>Records/Folder ID: <strong>{billingWindow.records_folder_id}</strong></p><p>Date and Time: <strong>{new Date(billingWindow.date_time).toLocaleString('en-GH')}</strong></p></div></div>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 py-4 border-b border-border"><div><p className="text-xs text-muted-foreground">Patient Name</p><p className="font-semibold">{billingWindow.patient_name}</p></div><div><p className="text-xs text-muted-foreground">Patient Type</p><p className="font-semibold">{billingWindow.patient_type}</p></div>{billingWindow.patient_type === 'Insured' && <div><p className="text-xs text-muted-foreground">Insurance Name</p><p className="font-semibold">{billingWindow.insurance_name}</p></div>}<div><p className="text-xs text-muted-foreground">Encounter ID</p><p className="font-mono text-xs">{billingWindow.encounter_id ?? '—'}</p></div></div>
            <div className="overflow-x-auto mt-4"><table className="w-full text-sm border-collapse"><thead><tr className="bg-muted/70"><th className="border border-border px-3 py-2 text-left">S/n</th><th className="border border-border px-3 py-2 text-left">Description</th><th className="border border-border px-3 py-2 text-right">Charge</th>{billingWindow.patient_type === 'Insured' && <th className="border border-border px-3 py-2 text-right">Insurance Charge</th>}{billingWindow.patient_type === 'Insured' && <th className="border border-border px-3 py-2 text-right">Top up</th>}</tr></thead><tbody>{billingWindow.items.map((item,index) => <tr key={item.invoice_item_id}><td className="border border-border px-3 py-2">{index + 1}</td><td className="border border-border px-3 py-2">{item.description}</td><td className="border border-border px-3 py-2 text-right">{money(item.charge ?? item.amount)}</td>{billingWindow.patient_type === 'Insured' && <td className="border border-border px-3 py-2 text-right">{money(item.insurance_charge)}</td>}{billingWindow.patient_type === 'Insured' && <td className="border border-border px-3 py-2 text-right">{money(item.top_up)}</td>}</tr>)}</tbody></table></div>
            <div className="ml-auto max-w-md mt-5 border-t-2 border-border"><div className="flex justify-between py-2 border-b border-border"><span>Total amount</span><strong>{money(billingWindow.total_amount)}</strong></div><div className="flex justify-between py-2 border-b border-border"><span>Credit balance / Deposit</span><strong>{money(billingWindow.credit_balance)}</strong></div><div className="flex justify-between py-3 text-lg"><span>{billingWindow.amount_due < 0 ? 'Credit' : 'Amount Due'}</span><strong>{money(Math.abs(billingWindow.amount_due))}</strong></div></div>
            <p className="mt-5 text-sm italic border-t border-border pt-4">({amountInWords(billingWindow.patient_type === 'Insured' ? billingWindow.top_up_total : billingWindow.total_amount)}) being payment of medical bill</p>
          </section>

          {patientId && <section className="card-medical p-5 print:hidden"><div className="flex items-center gap-2 mb-3"><Plus className="w-4 h-4 text-primary" /><div><h2 className="font-semibold">Additional service</h2><p className="text-xs text-muted-foreground">Add a tariffed service without leaving the patient billing window.</p></div></div><div className="grid gap-2 md:grid-cols-[1fr_1fr_110px_auto] items-end"><input value={walkInSearch} onChange={(e) => setWalkInSearch(e.target.value)} className="input-medical" placeholder="Search service or code" /><select value={walkInCode} onChange={(e) => setWalkInCode(e.target.value)} className="input-medical"><option value="">Select service tariff…</option>{filteredTariffs.map((t) => <option key={t.id} value={t.service_code}>{t.service_name} · {money(Number(t.amount))}</option>)}</select><input type="number" min={1} value={walkInQty} onChange={(e) => setWalkInQty(Number(e.target.value))} className="input-medical" aria-label="Service quantity" /><button type="button" onClick={() => void addWalkIn()} className="btn-primary">Add</button></div>{canCreateServices && walkInSearch.trim() && filteredTariffs.length === 0 && <button type="button" onClick={() => setCreateServiceName(walkInSearch.trim())} className="btn-secondary mt-2">Add {walkInSearch.trim()} to catalogue</button>}</section>}

          <p className="text-xs text-muted-foreground print:hidden">Invoice: {billingWindow.account_id} · Encounter: {billingWindow.encounter_id ?? 'not linked'} · Operator: {user?.email ?? 'authenticated user'}</p>
        </div>}
        {!billingWindow && !loading && patientId && <div className="card-medical p-10 text-center text-muted-foreground">Select a patient to prepare the current billing window.</div>}
      </OperationalWorklistShell>
    </>
  );
}
