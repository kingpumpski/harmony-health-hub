import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { CreditCard, Plus, Receipt, ShieldCheck, AlertCircle } from 'lucide-react';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string; insurance_provider: string | null; insurance_number: string | null }
interface Invoice {
  id: string; invoice_number: string; patient_id: string; total_amount: number;
  paid_amount: number; outstanding_amount: number; insurance_covered: number; status: string; created_at: string;
}
interface InvoiceItem { id: string; invoice_id: string; description: string; quantity: number; unit_price: number; amount: number; category: string | null }

export default function Billing() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [selected, setSelected] = useState<Invoice | null>(null);
  const [items, setItems] = useState<InvoiceItem[]>([]);

  // new invoice
  const [pid, setPid] = useState('');

  // new item
  const [desc, setDesc] = useState('');
  const [qty, setQty] = useState(1);
  const [price, setPrice] = useState(0);
  const [cat, setCat] = useState('consultation');

  // payment
  const [payAmount, setPayAmount] = useState(0);
  const [payMethod, setPayMethod] = useState('cash');

  const selectedPatient = selected ? patients.find((p) => p.id === selected.patient_id) : null;

  const loadAll = async () => {
    const [{ data: pts }, { data: invs }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name, patient_code, insurance_provider, insurance_number').limit(200),
      supabase.from('invoices').select('*').order('created_at', { ascending: false }).limit(50),
    ]);
    setPatients(pts ?? []);
    setInvoices(invs ?? []);
  };

  const loadItems = async (invoiceId: string) => {
    const { data } = await supabase.from('invoice_items').select('*').eq('invoice_id', invoiceId);
    setItems(data ?? []);
  };

  useEffect(() => { loadAll(); }, []);
  useEffect(() => { if (selected) loadItems(selected.id); }, [selected]);

  const createInvoice = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return;
    const number = `INV-${Date.now().toString().slice(-8)}`;
    const { data, error } = await supabase.from('invoices').insert({
      invoice_number: number, patient_id: pid, total_amount: 0, created_by: user?.id,
    }).select().single();
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Invoice created' });
    setPid('');
    setSelected(data as Invoice);
    loadAll();
  };

  const addItem = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selected || !desc) return;
    const amount = qty * price;
    const { error } = await supabase.from('invoice_items').insert({
      invoice_id: selected.id, description: desc, quantity: qty, unit_price: price, amount, category: cat,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });

    // recompute total
    const { data: all } = await supabase.from('invoice_items').select('amount').eq('invoice_id', selected.id);
    const total = (all ?? []).reduce((s, r: any) => s + Number(r.amount), 0);
    await supabase.from('invoices').update({ total_amount: total }).eq('id', selected.id);

    setDesc(''); setQty(1); setPrice(0);
    loadItems(selected.id);
    loadAll();
    const fresh = await supabase.from('invoices').select('*').eq('id', selected.id).single();
    setSelected(fresh.data as Invoice);
  };

  const recordPayment = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selected || payAmount <= 0) return;
    const { error } = await supabase.from('payments').insert({
      invoice_id: selected.id, patient_id: selected.patient_id,
      amount: payAmount, method: payMethod, received_by: user?.id,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Payment recorded' });
    setPayAmount(0);
    const fresh = await supabase.from('invoices').select('*').eq('id', selected.id).single();
    setSelected(fresh.data as Invoice);
    loadAll();
  };

  const submitClaim = async () => {
    if (!selected || !selectedPatient?.insurance_provider) return;
    const claimAmount = Number(selected.total_amount) - Number(selected.paid_amount);
    const { error } = await supabase.from('insurance_claims').insert({
      invoice_id: selected.id, patient_id: selected.patient_id,
      provider: selectedPatient.insurance_provider, policy_number: selectedPatient.insurance_number,
      amount_claimed: claimAmount,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Insurance claim submitted' });
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
          <CreditCard className="w-6 h-6 text-primary" /> Billing & Insurance
        </h1>
        <p className="text-muted-foreground">Invoices, payments, and insurance claims.</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[360px_1fr]">
        <div className="space-y-4">
          <form onSubmit={createInvoice} className="card-medical p-5 space-y-3">
            <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New Invoice</h2>
            <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full">
              <option value="">Select patient…</option>
              {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
            </select>
            <button className="btn-primary w-full">Create</button>
          </form>

          <div className="card-medical p-5">
            <h2 className="font-semibold mb-3">Recent Invoices</h2>
            <div className="space-y-2 max-h-[480px] overflow-auto">
              {invoices.map((i) => {
                const p = patients.find((x) => x.id === i.patient_id);
                return (
                  <button key={i.id} onClick={() => setSelected(i)}
                    className={`w-full text-left rounded-xl border p-3 ${selected?.id === i.id ? 'border-primary bg-primary/5' : 'border-border hover:bg-accent/40'}`}>
                    <div className="flex justify-between">
                      <div>
                        <p className="font-medium text-sm">{i.invoice_number}</p>
                        <p className="text-xs text-muted-foreground">{p ? `${p.first_name} ${p.last_name}` : '—'}</p>
                      </div>
                      <span className={`text-xs px-2 py-0.5 rounded-full ${
                        i.status === 'paid' ? 'bg-success/15 text-success' :
                        i.status === 'partially_paid' ? 'bg-warning/15 text-warning' :
                        'bg-muted text-muted-foreground'
                      }`}>{i.status}</span>
                    </div>
                    <div className="text-xs mt-1">Total ₵{Number(i.total_amount).toFixed(2)} · Outstanding ₵{Number(i.outstanding_amount).toFixed(2)}</div>
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        <div className="card-medical p-6 min-h-[400px]">
          {!selected ? (
            <div className="h-full flex items-center justify-center text-muted-foreground">
              Select or create an invoice.
            </div>
          ) : (
            <div className="space-y-6">
              {selectedPatient?.insurance_provider && (
                <div className="rounded-xl border border-primary/30 bg-primary/5 p-3 flex items-center gap-2 text-sm">
                  <ShieldCheck className="w-4 h-4 text-primary" />
                  <span><strong>Insurance:</strong> {selectedPatient.insurance_provider} ({selectedPatient.insurance_number})</span>
                </div>
              )}

              <div className="flex justify-between items-start">
                <div>
                  <h2 className="text-lg font-semibold flex items-center gap-2"><Receipt className="w-5 h-5" /> {selected.invoice_number}</h2>
                  <p className="text-sm text-muted-foreground">{selectedPatient ? `${selectedPatient.first_name} ${selectedPatient.last_name}` : ''}</p>
                </div>
                <div className="text-right">
                  <p className="text-2xl font-bold">₵{Number(selected.total_amount).toFixed(2)}</p>
                  <p className="text-xs text-muted-foreground">Paid ₵{Number(selected.paid_amount).toFixed(2)} · Outstanding ₵{Number(selected.outstanding_amount).toFixed(2)}</p>
                </div>
              </div>

              <section>
                <h3 className="font-semibold mb-2">Line Items</h3>
                <form onSubmit={addItem} className="grid grid-cols-2 md:grid-cols-5 gap-2 mb-3">
                  <input value={desc} onChange={(e) => setDesc(e.target.value)} className="input-medical md:col-span-2" placeholder="Description" />
                  <input type="number" value={qty} onChange={(e) => setQty(Number(e.target.value))} min={1} className="input-medical" placeholder="Qty" />
                  <input type="number" value={price} onChange={(e) => setPrice(Number(e.target.value))} step="0.01" className="input-medical" placeholder="Unit price" />
                  <select value={cat} onChange={(e) => setCat(e.target.value)} className="input-medical">
                    <option value="consultation">Consultation</option>
                    <option value="lab">Lab</option>
                    <option value="pharmacy">Pharmacy</option>
                    <option value="procedure">Procedure</option>
                    <option value="ward">Ward</option>
                  </select>
                  <button className="btn-primary md:col-span-5">Add item</button>
                </form>
                <table className="w-full text-sm">
                  <thead className="text-xs text-muted-foreground"><tr><th className="text-left">Item</th><th>Qty</th><th>Price</th><th className="text-right">Amount</th></tr></thead>
                  <tbody>
                    {items.map((it) => (
                      <tr key={it.id} className="border-t border-border">
                        <td className="py-2">{it.description} <span className="text-xs text-muted-foreground">({it.category})</span></td>
                        <td className="text-center">{it.quantity}</td>
                        <td className="text-center">₵{Number(it.unit_price).toFixed(2)}</td>
                        <td className="text-right">₵{Number(it.amount).toFixed(2)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </section>

              <section>
                <h3 className="font-semibold mb-2">Record Payment</h3>
                <form onSubmit={recordPayment} className="grid grid-cols-3 gap-2">
                  <input type="number" value={payAmount} onChange={(e) => setPayAmount(Number(e.target.value))} step="0.01" className="input-medical" placeholder="Amount" />
                  <select value={payMethod} onChange={(e) => setPayMethod(e.target.value)} className="input-medical">
                    <option value="cash">Cash</option>
                    <option value="card">Card</option>
                    <option value="mobile_money">Mobile Money</option>
                    <option value="insurance">Insurance</option>
                    <option value="advance">Advance Payment</option>
                  </select>
                  <button className="btn-primary">Record</button>
                </form>
              </section>

              {selectedPatient?.insurance_provider && Number(selected.outstanding_amount) > 0 && (
                <section className="border-t pt-4">
                  <button onClick={submitClaim} className="btn-ghost inline-flex items-center gap-2 text-sm">
                    <AlertCircle className="w-4 h-4" /> Submit insurance claim for outstanding balance
                  </button>
                </section>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
