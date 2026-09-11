import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Pill, Package, Truck, AlertTriangle, CheckCircle2, XCircle, Clock, CreditCard } from 'lucide-react';
import { playSuccessSound } from '@/lib/sounds';
import { notify } from '@/lib/notifications';
import { createServiceOrder, type ServiceOrderStatus } from '@/lib/workflow';

interface Inv { id: string; drug_name: string; strength: string; stock_quantity: number; reorder_level: number; unit_price: number }
interface GR { id: string; drug_name: string; quantity: number; unit_cost: number; supplier: string | null; invoice_number: string | null; expiry_date: string | null; status: string; inventory_id: string | null; created_at: string; rejection_reason: string | null }
interface Prescription { id: string; patient_id: string; medication: string; dosage: string; frequency: string; duration: string; patients?: { first_name: string; last_name: string } | null }

export default function Pharmacy() {
  const { user } = useAuth();
  const [inventory, setInventory] = useState<Inv[]>([]);
  const [tab, setTab] = useState<'dispense' | 'inventory' | 'receipt' | 'approvals'>('dispense');
  const [prescriptions, setPrescriptions] = useState<Prescription[]>([]);
  const [receipts, setReceipts] = useState<GR[]>([]);

  const [grInv, setGrInv] = useState(''); const [grQty, setGrQty] = useState(0);
  const [grSupplier, setGrSupplier] = useState(''); const [grInvoice, setGrInvoice] = useState('');
  const [grExpiry, setGrExpiry] = useState(''); const [grCost, setGrCost] = useState(0);

  const [niName, setNiName] = useState(''); const [niStrength, setNiStrength] = useState('');
  const [niStock, setNiStock] = useState(0); const [niReorder, setNiReorder] = useState(20); const [niPrice, setNiPrice] = useState(0);

  const [dispenseInv, setDispenseInv] = useState<Record<string, string>>({});
  const [dispenseQty, setDispenseQty] = useState<Record<string, number>>({});

  const load = async () => {
    const [{ data: inv }, { data: rx }, { data: gr }] = await Promise.all([
      supabase.from('pharmacy_inventory').select('*').order('drug_name'),
      supabase.from('prescriptions').select('*, patients(first_name,last_name)').eq('status', 'pending').order('created_at', { ascending: false }).limit(50),
      supabase.from('pharmacy_goods_receipts').select('*').order('created_at', { ascending: false }).limit(50),
    ]);
    setInventory((inv ?? []) as Inv[]);
    setPrescriptions((rx ?? []) as Prescription[]);
    setReceipts((gr ?? []) as GR[]);
  };

  useEffect(() => {
    void load();
    const ch = supabase.channel('pharma-inv').on('postgres_changes', { event: '*', schema: 'public', table: 'pharmacy_inventory' }, () => void load()).subscribe();
    return () => { void supabase.removeChannel(ch); };
  }, []);

  const getPaymentGate = async (rxId: string, patientId: string, inv: Inv, qty: number) => {
    const amount = Math.max(0, Number(inv.unit_price || 0) * qty);
    if (amount <= 0) return true;

    const { data: existing, error } = await supabase
      .from('service_orders')
      .select('id,status')
      .eq('related_entity_id', rxId)
      .eq('department', 'pharmacy')
      .neq('status', 'cancelled')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) throw error;

    let status = existing?.status as ServiceOrderStatus | undefined;
    if (!existing) {
      await createServiceOrder({
        patientId,
        department: 'pharmacy',
        serviceName: `Dispense: ${inv.drug_name}`,
        amount,
        relatedEntityId: rxId,
        orderType: 'drug',
        serviceCode: inv.id,
        notes: `Prescription ${rxId}; quantity ${qty}`,
        requestedBy: user?.id,
      });
      status = 'pending_payment_approval';
    }

    if (!status || !['released', 'in_progress', 'completed'].includes(status)) {
      toast({ title: 'Payment approval required', description: 'Accounts must release this medication charge before dispensing.', variant: 'destructive' });
      setTab('dispense');
      return false;
    }
    return true;
  };

  const dispense = async (rx: Prescription) => {
    const invId = dispenseInv[rx.id] || null;
    const qty = Math.max(1, dispenseQty[rx.id] || 1);
    const inv = inventory.find(i => i.id === invId);

    if (!inv) return toast({ title: 'Select inventory item', description: 'Match the prescription to an inventory item before dispensing.', variant: 'destructive' });
    if (inv.stock_quantity < qty) return toast({ title: 'Insufficient stock', description: `Only ${inv.stock_quantity} units available.`, variant: 'destructive' });

    try {
      if (!(await getPaymentGate(rx.id, rx.patient_id, inv, qty))) return;
    } catch (error) {
      return toast({ title: 'Payment gate failed', description: error instanceof Error ? error.message : 'Unable to verify payment approval.', variant: 'destructive' });
    }

    const { error: maErr } = await supabase.from('medication_administrations').insert({
      prescription_id: rx.id,
      patient_id: rx.patient_id,
      inventory_id: inv.id,
      drug_name: inv.drug_name,
      dose: rx.dosage,
      quantity_dispensed: qty,
      administered_by: user?.id,
    });
    if (maErr) return toast({ title: 'Failed', description: maErr.message, variant: 'destructive' });

    const { error: rxErr } = await supabase.from('prescriptions').update({
      status: 'dispensed', dispensed_by: user?.id, dispensed_at: new Date().toISOString(),
    }).eq('id', rx.id);
    if (rxErr) return toast({ title: 'Dispense recorded but prescription update failed', description: rxErr.message, variant: 'destructive' });

    notify({ recipientUserId: rx.patient_id, title: 'Medication dispensed', message: `${rx.medication} (${rx.dosage}) has been dispensed.`, severity: 'success', category: 'prescription', relatedPatientId: rx.patient_id });
    playSuccessSound();
    toast({ title: 'Dispensed', description: `${qty} × ${inv.drug_name}` });
    void load();
  };

  const submitReceipt = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!grInv || grQty <= 0) return;
    const inv = inventory.find(i => i.id === grInv);
    const { error } = await supabase.from('pharmacy_goods_receipts').insert({
      inventory_id: grInv, drug_name: inv?.drug_name ?? '', quantity: grQty,
      unit_cost: grCost, supplier: grSupplier, invoice_number: grInvoice, expiry_date: grExpiry || null, received_by: user?.id,
      status: 'pending',
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    playSuccessSound();
    notify({ recipientRole: 'admin', title: 'Goods receipt awaiting approval', message: `${grQty} × ${inv?.drug_name} from ${grSupplier || 'supplier'}`, severity: 'info', category: 'other', link: '/pharmacy' });
    notify({ recipientRole: 'pharmacist', title: 'Goods receipt submitted', message: `${grQty} × ${inv?.drug_name}`, severity: 'info', category: 'other' });
    toast({ title: 'Goods receipt submitted', description: 'Awaiting approval before stock is updated.' });
    setGrInv(''); setGrQty(0); setGrSupplier(''); setGrInvoice(''); setGrExpiry(''); setGrCost(0);
    void load();
  };

  const approveReceipt = async (g: GR) => {
    const { error } = await supabase.from('pharmacy_goods_receipts').update({ status: 'approved', approved_by: user?.id, approved_at: new Date().toISOString() }).eq('id', g.id);
    if (error) return toast({ title: 'Approve failed', description: error.message, variant: 'destructive' });
    playSuccessSound(); notify({ recipientRole: 'pharmacist', title: 'Goods receipt approved', message: `${g.quantity} × ${g.drug_name} added to inventory.`, severity: 'success', category: 'other' });
    toast({ title: 'Approved', description: 'Inventory updated.' }); void load();
  };

  const rejectReceipt = async (g: GR) => {
    const reason = prompt('Reason for rejection?') ?? '';
    if (!reason) return;
    const { error } = await supabase.from('pharmacy_goods_receipts').update({ status: 'rejected', rejection_reason: reason, approved_by: user?.id, approved_at: new Date().toISOString() }).eq('id', g.id);
    if (error) return toast({ title: 'Reject failed', variant: 'destructive' });
    notify({ recipientRole: 'pharmacist', title: 'Goods receipt rejected', message: `${g.drug_name}: ${reason}`, severity: 'warning', category: 'other' });
    toast({ title: 'Rejected' }); void load();
  };

  const addInventory = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!niName) return;
    const { error } = await supabase.from('pharmacy_inventory').insert({ drug_name: niName, strength: niStrength, stock_quantity: niStock, reorder_level: niReorder, unit_price: niPrice });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    playSuccessSound(); toast({ title: 'Drug added to inventory' });
    setNiName(''); setNiStrength(''); setNiStock(0); setNiReorder(20); setNiPrice(0); void load();
  };

  const lowStock = inventory.filter(i => i.stock_quantity <= i.reorder_level);
  const pendingReceipts = receipts.filter(r => r.status === 'pending');

  return (
    <div className="space-y-6 animate-fade-in">
      <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Pill className="w-6 h-6 text-primary" /> Pharmacy</h1><p className="text-muted-foreground">Dispense, manage inventory, record goods receipts, and approve stock.</p></div>
      <div className="rounded-xl border border-primary/20 bg-primary/5 p-3 flex items-start gap-2 text-sm"><CreditCard className="w-4 h-4 text-primary mt-0.5 shrink-0" /><p className="text-muted-foreground">Chargeable medication is routed to Accounts first. Dispensing is blocked until payment or an authorised override releases the order.</p></div>

      <div className="flex gap-2 border-b border-border flex-wrap">
        {(['dispense','inventory','receipt','approvals'] as const).map(t => <button key={t} onClick={() => setTab(t)} className={`px-4 py-2 text-sm font-medium border-b-2 transition ${tab===t ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}>{t === 'dispense' ? 'Dispense' : t === 'inventory' ? 'Inventory' : t === 'receipt' ? 'New goods receipt' : `Approvals${pendingReceipts.length ? ` (${pendingReceipts.length})` : ''}`}</button>)}
      </div>

      {lowStock.length > 0 && <div className="rounded-xl bg-warning/10 border border-warning/30 p-3 flex items-start gap-2 text-sm"><AlertTriangle className="w-4 h-4 text-warning shrink-0 mt-0.5" /><div><p className="font-medium text-warning">{lowStock.length} item(s) below reorder level</p><p className="text-xs text-muted-foreground">{lowStock.map(i => i.drug_name).join(', ')}</p></div></div>}

      {tab === 'dispense' && <div className="card-medical p-5"><h2 className="font-semibold mb-3">Pending prescriptions</h2><div className="space-y-3">{prescriptions.map(p => <div key={p.id} className="rounded-xl border border-border p-3 space-y-2"><div><p className="font-medium">{p.medication}</p><p className="text-xs text-muted-foreground">{p.patients?.first_name} {p.patients?.last_name} · {p.dosage} · {p.frequency} · {p.duration}</p></div><div className="flex flex-wrap gap-2 items-center"><select value={dispenseInv[p.id] ?? ''} onChange={e => setDispenseInv({ ...dispenseInv, [p.id]: e.target.value })} className="input-medical text-xs flex-1 min-w-[200px]"><option value="">Match to inventory item…</option>{inventory.map(i => <option key={i.id} value={i.id} disabled={i.stock_quantity <= 0}>{i.drug_name} {i.strength} ({i.stock_quantity} in stock)</option>)}</select><input type="number" min={1} value={dispenseQty[p.id] ?? 1} onChange={e => setDispenseQty({ ...dispenseQty, [p.id]: Number(e.target.value) })} className="input-medical text-xs w-24" placeholder="Qty" /><button onClick={() => void dispense(p)} className="btn-primary text-xs">Dispense</button></div></div>)}{prescriptions.length === 0 && <p className="text-sm text-muted-foreground">No pending prescriptions.</p>}</div></div>}

      {tab === 'inventory' && <div className="grid lg:grid-cols-[400px_1fr] gap-6"><form onSubmit={addInventory} className="card-medical p-5 space-y-3 h-fit"><h2 className="font-semibold flex items-center gap-2"><Package className="w-4 h-4" /> Add drug</h2><input value={niName} onChange={e=>setNiName(e.target.value)} placeholder="Drug name" className="input-medical w-full" /><input value={niStrength} onChange={e=>setNiStrength(e.target.value)} placeholder="Strength (e.g. 500mg)" className="input-medical w-full" /><input type="number" value={niStock} onChange={e=>setNiStock(Number(e.target.value))} placeholder="Initial stock" className="input-medical w-full" /><input type="number" value={niReorder} onChange={e=>setNiReorder(Number(e.target.value))} placeholder="Reorder level" className="input-medical w-full" /><input type="number" step="0.01" value={niPrice} onChange={e=>setNiPrice(Number(e.target.value))} placeholder="Unit price (GHS)" className="input-medical w-full" /><button className="btn-primary w-full">Add</button></form><div className="card-medical p-5"><h2 className="font-semibold mb-3">Stock levels</h2><div className="space-y-2">{inventory.map(i => <div key={i.id} className="rounded-xl border border-border p-3 flex justify-between items-center text-sm"><div><span className="font-medium">{i.drug_name}</span> <span className="text-muted-foreground">{i.strength}</span></div><span className={i.stock_quantity <= i.reorder_level ? 'text-critical font-semibold' : 'text-success font-semibold'}>{i.stock_quantity} units</span></div>)}</div></div></div>}

      {tab === 'receipt' && <form onSubmit={submitReceipt} className="card-medical p-6 grid md:grid-cols-2 gap-3 max-w-2xl"><h2 className="font-semibold flex items-center gap-2 md:col-span-2"><Truck className="w-4 h-4" /> Submit goods receipt</h2><p className="text-xs text-muted-foreground md:col-span-2">Submitted receipts wait in <strong>Approvals</strong>; stock only updates after approval.</p><select value={grInv} onChange={e=>setGrInv(e.target.value)} className="input-medical md:col-span-2" required><option value="">Select drug from inventory…</option>{inventory.map(i => <option key={i.id} value={i.id}>{i.drug_name} ({i.strength})</option>)}</select><input type="number" value={grQty || ''} onChange={e=>setGrQty(Number(e.target.value))} placeholder="Quantity received" className="input-medical" required /><input type="number" step="0.01" value={grCost || ''} onChange={e=>setGrCost(Number(e.target.value))} placeholder="Unit cost (GHS)" className="input-medical" /><input value={grSupplier} onChange={e=>setGrSupplier(e.target.value)} placeholder="Supplier" className="input-medical" /><input value={grInvoice} onChange={e=>setGrInvoice(e.target.value)} placeholder="Invoice number" className="input-medical" /><input type="date" value={grExpiry} onChange={e=>setGrExpiry(e.target.value)} className="input-medical md:col-span-2" /><button className="btn-primary md:col-span-2">Submit for approval</button></form>}

      {tab === 'approvals' && <div className="card-medical p-5"><h2 className="font-semibold mb-3">Goods receipts</h2><div className="space-y-2">{receipts.map(g => <div key={g.id} className="rounded-xl border border-border p-3 flex flex-wrap justify-between items-center gap-3 text-sm"><div><p className="font-medium flex items-center gap-2">{g.status === 'approved' && <CheckCircle2 className="w-4 h-4 text-success" />}{g.status === 'rejected' && <XCircle className="w-4 h-4 text-critical" />}{g.status === 'pending' && <Clock className="w-4 h-4 text-warning" />}{g.quantity} × {g.drug_name}</p><p className="text-xs text-muted-foreground">{g.supplier ?? '—'} · Invoice {g.invoice_number ?? '—'} · GHS {g.unit_cost ?? 0}/unit · Exp {g.expiry_date ?? '—'}</p>{g.rejection_reason && <p className="text-xs text-critical mt-1">Rejected: {g.rejection_reason}</p>}</div>{g.status === 'pending' && <div className="flex gap-2"><button onClick={() => void approveReceipt(g)} className="btn-primary text-xs">Approve</button><button onClick={() => void rejectReceipt(g)} className="btn-ghost text-xs text-critical">Reject</button></div>}</div>)}{receipts.length === 0 && <p className="text-sm text-muted-foreground">No goods receipts recorded.</p>}</div></div>}
    </div>
  );
}
