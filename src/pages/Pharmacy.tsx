import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Pill, Package, Truck, AlertTriangle } from 'lucide-react';

const successBeep = () => {
  try {
    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    const o = ctx.createOscillator(); const g = ctx.createGain();
    o.connect(g); g.connect(ctx.destination);
    o.frequency.value = 988; g.gain.setValueAtTime(0.1, ctx.currentTime);
    o.start(); o.stop(ctx.currentTime + 0.15);
  } catch {}
};

interface Inv { id: string; drug_name: string; strength: string; stock_quantity: number; reorder_level: number; unit_price: number }

export default function Pharmacy() {
  const { user } = useAuth();
  const [inventory, setInventory] = useState<Inv[]>([]);
  const [tab, setTab] = useState<'dispense' | 'inventory' | 'receipt'>('dispense');
  const [prescriptions, setPrescriptions] = useState<any[]>([]);

  // Goods receipt form
  const [grInv, setGrInv] = useState(''); const [grQty, setGrQty] = useState(0);
  const [grSupplier, setGrSupplier] = useState(''); const [grInvoice, setGrInvoice] = useState('');
  const [grExpiry, setGrExpiry] = useState(''); const [grCost, setGrCost] = useState(0);

  // New inventory form
  const [niName, setNiName] = useState(''); const [niStrength, setNiStrength] = useState('');
  const [niStock, setNiStock] = useState(0); const [niReorder, setNiReorder] = useState(20); const [niPrice, setNiPrice] = useState(0);

  const load = async () => {
    const [{ data: inv }, { data: rx }] = await Promise.all([
      supabase.from('pharmacy_inventory').select('*').order('drug_name'),
      supabase.from('prescriptions').select('*, patients(first_name,last_name)').eq('status', 'pending').order('created_at', { ascending: false }).limit(50),
    ]);
    setInventory((inv ?? []) as Inv[]);
    setPrescriptions(rx ?? []);
  };

  useEffect(() => {
    load();
    const ch = supabase.channel('pharma-inv').on('postgres_changes', { event: '*', schema: 'public', table: 'pharmacy_inventory' }, load).subscribe();
    return () => { supabase.removeChannel(ch); };
  }, []);

  const dispense = async (rxId: string) => {
    const { error } = await supabase.from('prescriptions').update({ status: 'dispensed', dispensed_by: user?.id, dispensed_at: new Date().toISOString() }).eq('id', rxId);
    if (error) return toast({ title: 'Failed', variant: 'destructive' });
    successBeep(); toast({ title: 'Dispensed' });
    load();
  };

  const submitReceipt = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!grInv || grQty <= 0) return;
    const inv = inventory.find(i => i.id === grInv);
    const { error } = await supabase.from('pharmacy_goods_receipts').insert({
      inventory_id: grInv, drug_name: inv?.drug_name ?? '', quantity: grQty,
      unit_cost: grCost, supplier: grSupplier, invoice_number: grInvoice, expiry_date: grExpiry || null, received_by: user?.id,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    successBeep();
    await supabase.from('notifications').insert({ recipient_role: 'pharmacist', title: 'Stock received', message: `${grQty} × ${inv?.drug_name}`, severity: 'success', category: 'other' });
    toast({ title: 'Goods received', description: 'Inventory updated.' });
    setGrInv(''); setGrQty(0); setGrSupplier(''); setGrInvoice(''); setGrExpiry(''); setGrCost(0);
  };

  const addInventory = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!niName) return;
    const { error } = await supabase.from('pharmacy_inventory').insert({
      drug_name: niName, strength: niStrength, stock_quantity: niStock, reorder_level: niReorder, unit_price: niPrice,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    successBeep(); toast({ title: 'Drug added to inventory' });
    setNiName(''); setNiStrength(''); setNiStock(0); setNiReorder(20); setNiPrice(0);
  };

  const lowStock = inventory.filter(i => i.stock_quantity <= i.reorder_level);

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Pill className="w-6 h-6 text-primary" /> Pharmacy</h1>
        <p className="text-muted-foreground">Dispense, manage inventory, and record goods receipts.</p>
      </div>

      <div className="flex gap-2 border-b border-border">
        {(['dispense','inventory','receipt'] as const).map(t => (
          <button key={t} onClick={() => setTab(t)} className={`px-4 py-2 text-sm font-medium border-b-2 transition ${tab===t ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}>
            {t === 'dispense' ? 'Dispense' : t === 'inventory' ? 'Inventory' : 'Goods receipt'}
          </button>
        ))}
      </div>

      {lowStock.length > 0 && (
        <div className="rounded-xl bg-warning/10 border border-warning/30 p-3 flex items-start gap-2 text-sm">
          <AlertTriangle className="w-4 h-4 text-warning shrink-0 mt-0.5" />
          <div>
            <p className="font-medium text-warning">{lowStock.length} item(s) below reorder level</p>
            <p className="text-xs text-muted-foreground">{lowStock.map(i => i.drug_name).join(', ')}</p>
          </div>
        </div>
      )}

      {tab === 'dispense' && (
        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Pending prescriptions</h2>
          <div className="space-y-2">
            {prescriptions.map(p => (
              <div key={p.id} className="rounded-xl border border-border p-3 flex justify-between items-center">
                <div>
                  <p className="font-medium">{p.medication}</p>
                  <p className="text-xs text-muted-foreground">{p.patients?.first_name} {p.patients?.last_name} · {p.dosage} · {p.frequency} · {p.duration}</p>
                </div>
                <button onClick={() => dispense(p.id)} className="btn-primary text-xs">Dispense</button>
              </div>
            ))}
            {prescriptions.length === 0 && <p className="text-sm text-muted-foreground">No pending prescriptions.</p>}
          </div>
        </div>
      )}

      {tab === 'inventory' && (
        <div className="grid lg:grid-cols-[400px_1fr] gap-6">
          <form onSubmit={addInventory} className="card-medical p-5 space-y-3 h-fit">
            <h2 className="font-semibold flex items-center gap-2"><Package className="w-4 h-4" /> Add drug</h2>
            <input value={niName} onChange={e=>setNiName(e.target.value)} placeholder="Drug name" className="input-medical w-full" />
            <input value={niStrength} onChange={e=>setNiStrength(e.target.value)} placeholder="Strength (e.g. 500mg)" className="input-medical w-full" />
            <input type="number" value={niStock} onChange={e=>setNiStock(Number(e.target.value))} placeholder="Initial stock" className="input-medical w-full" />
            <input type="number" value={niReorder} onChange={e=>setNiReorder(Number(e.target.value))} placeholder="Reorder level" className="input-medical w-full" />
            <input type="number" step="0.01" value={niPrice} onChange={e=>setNiPrice(Number(e.target.value))} placeholder="Unit price (GHS)" className="input-medical w-full" />
            <button className="btn-primary w-full">Add</button>
          </form>
          <div className="card-medical p-5">
            <h2 className="font-semibold mb-3">Stock levels</h2>
            <div className="space-y-2">
              {inventory.map(i => (
                <div key={i.id} className="rounded-xl border border-border p-3 flex justify-between items-center text-sm">
                  <div><span className="font-medium">{i.drug_name}</span> <span className="text-muted-foreground">{i.strength}</span></div>
                  <span className={i.stock_quantity <= i.reorder_level ? 'text-critical font-semibold' : 'text-success font-semibold'}>{i.stock_quantity} units</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {tab === 'receipt' && (
        <form onSubmit={submitReceipt} className="card-medical p-6 grid md:grid-cols-2 gap-3 max-w-2xl">
          <h2 className="font-semibold flex items-center gap-2 md:col-span-2"><Truck className="w-4 h-4" /> Record goods receipt</h2>
          <select value={grInv} onChange={e=>setGrInv(e.target.value)} className="input-medical md:col-span-2">
            <option value="">Select drug from inventory…</option>
            {inventory.map(i => <option key={i.id} value={i.id}>{i.drug_name} ({i.strength})</option>)}
          </select>
          <input type="number" value={grQty || ''} onChange={e=>setGrQty(Number(e.target.value))} placeholder="Quantity received" className="input-medical" />
          <input type="number" step="0.01" value={grCost || ''} onChange={e=>setGrCost(Number(e.target.value))} placeholder="Unit cost (GHS)" className="input-medical" />
          <input value={grSupplier} onChange={e=>setGrSupplier(e.target.value)} placeholder="Supplier" className="input-medical" />
          <input value={grInvoice} onChange={e=>setGrInvoice(e.target.value)} placeholder="Invoice number" className="input-medical" />
          <input type="date" value={grExpiry} onChange={e=>setGrExpiry(e.target.value)} className="input-medical md:col-span-2" />
          <button className="btn-primary md:col-span-2">Submit receipt</button>
        </form>
      )}
    </div>
  );
}
