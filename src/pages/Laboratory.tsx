import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { FlaskConical, Plus, CheckCircle2, ShieldCheck, AlertTriangle, LockKeyhole } from 'lucide-react';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string; email: string | null }
interface LabCatalogueItem {
  id: string; test_code: string; test_name: string; category: string | null; specimen_type: string | null;
  unit: string | null; reference_low: number | null; reference_high: number | null; reference_text: string | null;
  default_charge: number; active: boolean;
}
interface LabOrder {
  id: string; patient_id: string; test_name: string; test_category: string | null;
  priority: string; status: string; created_at: string; clinical_notes: string | null; lab_test_catalogue_id: string | null;
}
interface LabResult {
  id: string; lab_order_id: string; result_data: { value?: string } | null; interpretation: string | null;
  is_abnormal: boolean; status: string; entered_at: string; approved_at: string | null;
  numeric_value: number | null; unit: string | null; reference_low: number | null; reference_high: number | null; abnormal_flag: string | null;
}
interface CreateLabOrderResponse { lab_order_id: string; service_order_id: string; status: string }

export default function Laboratory() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [catalogue, setCatalogue] = useState<LabCatalogueItem[]>([]);
  const [orders, setOrders] = useState<LabOrder[]>([]);
  const [resultsByOrder, setResultsByOrder] = useState<Record<string, LabResult>>({});
  const [pid, setPid] = useState('');
  const [catalogueId, setCatalogueId] = useState('');
  const [testName, setTestName] = useState('');
  const [category, setCategory] = useState('');
  const [priority, setPriority] = useState('routine');
  const [notes, setNotes] = useState('');
  const [amount, setAmount] = useState('');
  const [resultFor, setResultFor] = useState<string | null>(null);
  const [resultText, setResultText] = useState('');
  const [numericValue, setNumericValue] = useState('');
  const [interpretation, setInterpretation] = useState('');
  const [isAbnormal, setIsAbnormal] = useState(false);

  const loadAll = async () => {
    const [{ data: pts }, { data: cat }, { data: ord }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name, patient_code, email').limit(200),
      supabase.from('lab_test_catalogue').select('*').eq('active', true).order('test_name'),
      supabase.from('lab_orders').select('*').order('created_at', { ascending: false }).limit(50),
    ]);
    setPatients(pts ?? []);
    setCatalogue((cat ?? []) as LabCatalogueItem[]);
    setOrders((ord ?? []) as LabOrder[]);
    if (ord?.length) {
      const { data: res } = await supabase.from('lab_results').select('*').in('lab_order_id', ord.map((o) => o.id));
      const map: Record<string, LabResult> = {};
      (res ?? []).forEach((r) => (map[r.lab_order_id] = r as LabResult));
      setResultsByOrder(map);
    } else setResultsByOrder({});
  };

  useEffect(() => { void loadAll(); }, []);

  const selectTest = (id: string) => {
    setCatalogueId(id);
    const item = catalogue.find((entry) => entry.id === id);
    if (!item) return;
    setTestName(item.test_name);
    setCategory(item.category ?? '');
    setAmount(String(item.default_charge));
  };

  const createOrder = async (e: React.FormEvent) => {
    e.preventDefault();
    const numericAmount = Number(amount);
    if (!pid || !testName || !Number.isFinite(numericAmount) || numericAmount < 0) {
      toast({ title: 'Complete the order details', description: 'Patient, test and a valid amount are required.', variant: 'destructive' });
      return;
    }
    const { data, error } = await supabase.rpc('create_lab_order_with_payment_gate', {
      _patient_id: pid, _test_name: testName, _test_category: category || null,
      _priority: priority, _clinical_notes: notes || null, _amount: numericAmount,
    } as never);
    if (error) {
      toast({ title: 'Failed to create lab order', description: error.message, variant: 'destructive' });
      return;
    }
    const created = data as unknown as CreateLabOrderResponse | null;
    if (created?.lab_order_id && catalogueId) {
      const { error: catalogueError } = await supabase.from('lab_orders').update({ lab_test_catalogue_id: catalogueId }).eq('id', created.lab_order_id);
      if (catalogueError) toast({ title: 'Order created with catalogue link warning', description: catalogueError.message });
    }
    setPid(''); setCatalogueId(''); setTestName(''); setCategory(''); setNotes(''); setPriority('routine'); setAmount('');
    toast({ title: numericAmount > 0 ? 'Lab order sent to Accounts' : 'Lab order created', description: numericAmount > 0 ? 'Laboratory work remains blocked until Accounts releases it.' : 'The order is available to the laboratory workflow.' });
    void loadAll();
  };

  const collectSample = async (id: string) => {
    const order = orders.find((item) => item.id === id);
    if (!order) return;
    const { data: gate, error: gateError } = await supabase.from('service_orders').select('status').eq('related_entity_id', id).eq('department', 'laboratory').maybeSingle();
    if (gateError) return toast({ title: 'Could not verify payment gate', description: gateError.message, variant: 'destructive' });
    if (gate && !['released', 'in_progress', 'completed'].includes(gate.status)) {
      return toast({ title: 'Payment approval required', description: 'Accounts must release this laboratory order before sample collection.', variant: 'destructive' });
    }
    const { error } = await supabase.from('lab_orders').update({ status: 'sample_collected', collected_by: user?.id, sample_collected_at: new Date().toISOString() }).eq('id', id);
    if (error) toast({ title: 'Could not collect sample', description: error.message, variant: 'destructive' }); else void loadAll();
  };

  const submitResult = async (orderId: string) => {
    const order = orders.find((item) => item.id === orderId);
    const item = catalogue.find((entry) => entry.id === order?.lab_test_catalogue_id);
    const parsedNumeric = numericValue.trim() === '' ? null : Number(numericValue);
    if (numericValue.trim() !== '' && !Number.isFinite(parsedNumeric)) return toast({ title: 'Invalid numeric result', description: 'Enter a valid number or leave the numeric field empty.', variant: 'destructive' });
    const { error } = await supabase.from('lab_results').insert({
      lab_order_id: orderId, result_data: { value: resultText }, interpretation,
      is_abnormal: isAbnormal, entered_by: user?.id, status: 'completed',
      numeric_value: parsedNumeric, unit: item?.unit ?? null,
      reference_low: item?.reference_low ?? null, reference_high: item?.reference_high ?? null,
      abnormal_flag: isAbnormal ? 'abnormal' : 'normal',
    } as never);
    if (error) return toast({ title: 'Failed to save result', description: error.message, variant: 'destructive' });
    await supabase.from('lab_orders').update({ status: 'completed' }).eq('id', orderId);
    setResultFor(null); setResultText(''); setNumericValue(''); setInterpretation(''); setIsAbnormal(false);
    toast({ title: 'Result submitted', description: 'The result is ready for clinical approval.' });
    void loadAll();
  };

  const approveResult = async (resultId: string, orderId: string, patientId: string) => {
    const { error } = await supabase.from('lab_results').update({ status: 'approved', approved_by: user?.id, approved_at: new Date().toISOString() }).eq('id', resultId);
    if (error) return toast({ title: 'Approval failed', description: error.message, variant: 'destructive' });
    const { error: orderError } = await supabase.from('lab_orders').update({ status: 'approved' }).eq('id', orderId);
    if (orderError) return toast({ title: 'Result approved but order update failed', description: orderError.message, variant: 'destructive' });
    const patient = patients.find((p) => p.id === patientId);
    if (patient?.email) {
      try { await supabase.functions.invoke('notify-lab-result', { body: { patientEmail: patient.email, patientName: `${patient.first_name} ${patient.last_name}`, testName: orders.find((o) => o.id === orderId)?.test_name ?? 'Lab Test' } }); }
      catch (e) { console.warn('Email notification failed', e); }
    }
    toast({ title: 'Result approved', description: 'Patient notified by email if available.' });
    void loadAll();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><FlaskConical className="w-6 h-6 text-primary" /> Laboratory</h1><p className="text-muted-foreground">Catalogue → order → payment approval → sample → structured result → approval.</p></div>
      <div className="grid gap-6 lg:grid-cols-[380px_1fr]">
        <form onSubmit={createOrder} className="card-medical p-5 space-y-3 h-fit">
          <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New Lab Order</h2>
          <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}</select>
          <select value={catalogueId} onChange={(e) => selectTest(e.target.value)} className="input-medical w-full"><option value="">Select catalogue test…</option>{catalogue.map((item) => <option key={item.id} value={item.id}>{item.test_code} — {item.test_name}{item.default_charge > 0 ? ` · GHS ${item.default_charge.toFixed(2)}` : ''}</option>)}</select>
          <input value={testName} onChange={(e) => setTestName(e.target.value)} className="input-medical w-full" placeholder="Test name" />
          <input value={category} onChange={(e) => setCategory(e.target.value)} className="input-medical w-full" placeholder="Category" />
          <select value={priority} onChange={(e) => setPriority(e.target.value)} className="input-medical w-full"><option value="routine">Routine</option><option value="urgent">Urgent</option><option value="stat">STAT</option></select>
          <input value={amount} onChange={(e) => setAmount(e.target.value)} className="input-medical w-full" inputMode="decimal" min="0" step="0.01" type="number" placeholder="Charge (GHS)" />
          <textarea value={notes} onChange={(e) => setNotes(e.target.value)} className="input-medical w-full" rows={2} placeholder="Clinical notes" />
          <button className="btn-primary w-full">Order Test</button>
          <p className="text-xs text-muted-foreground flex items-start gap-2"><LockKeyhole className="w-3.5 h-3.5 mt-0.5" /> Chargeable tests are blocked until Accounts releases them.</p>
        </form>
        <div className="card-medical p-5"><h2 className="font-semibold mb-3">Lab Queue</h2><div className="space-y-3">
          {orders.map((o) => { const p = patients.find((x) => x.id === o.patient_id); const result = resultsByOrder[o.id]; const item = catalogue.find((x) => x.id === o.lab_test_catalogue_id); return (
            <div key={o.id} className="rounded-xl border border-border p-4"><div className="flex justify-between items-start gap-3"><div><p className="font-medium">{o.test_name}</p><p className="text-xs text-muted-foreground">{p ? `${p.first_name} ${p.last_name}` : '—'} · {o.test_category ?? '—'} · {o.priority.toUpperCase()}</p>{item?.specimen_type && <p className="text-xs text-muted-foreground mt-1">Specimen: {item.specimen_type}{item.reference_text ? ` · Reference: ${item.reference_text}` : ''}</p>}</div><span className={`text-xs px-2 py-0.5 rounded-full ${o.status === 'approved' ? 'bg-success/15 text-success' : o.status === 'completed' ? 'bg-info/15 text-info' : o.status === 'sample_collected' ? 'bg-warning/15 text-warning' : 'bg-muted text-muted-foreground'}`}>{o.status.replace('_', ' ')}</span></div>
              {result?.is_abnormal && <div className="mt-2 flex items-center gap-2 text-critical text-xs"><AlertTriangle className="w-3 h-3" /> Abnormal result flagged</div>}
              <div className="mt-3 flex flex-wrap gap-2">{o.status === 'ordered' && <button onClick={() => void collectSample(o.id)} className="btn-ghost text-xs">Collect sample</button>}{o.status === 'sample_collected' && <button onClick={() => setResultFor(o.id)} className="btn-primary text-xs">Enter result</button>}{o.status === 'completed' && result && <button onClick={() => void approveResult(result.id, o.id, o.patient_id)} className="btn-primary text-xs inline-flex items-center gap-1"><ShieldCheck className="w-3 h-3" /> Approve & notify</button>}{o.status === 'approved' && <span className="text-xs text-success inline-flex items-center gap-1"><CheckCircle2 className="w-3 h-3" /> Approved</span>}</div>
              {resultFor === o.id && <div className="mt-3 space-y-2 border-t pt-3"><div className="grid gap-2 sm:grid-cols-2"><input value={numericValue} onChange={(e) => setNumericValue(e.target.value)} className="input-medical w-full" inputMode="decimal" placeholder={item?.unit ? `Numeric result (${item.unit})` : 'Numeric result'} />{item?.unit && <div className="input-medical bg-muted/30 text-sm flex items-center">Unit: {item.unit}</div>}</div><textarea value={resultText} onChange={(e) => setResultText(e.target.value)} className="input-medical w-full" rows={2} placeholder="Result values / narrative" /><input value={interpretation} onChange={(e) => setInterpretation(e.target.value)} className="input-medical w-full" placeholder="Interpretation" /><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={isAbnormal} onChange={(e) => setIsAbnormal(e.target.checked)} /> Abnormal result</label><div className="flex gap-2"><button type="button" onClick={() => void submitResult(o.id)} className="btn-primary text-xs">Submit</button><button type="button" onClick={() => setResultFor(null)} className="btn-ghost text-xs">Cancel</button></div></div>}
              {result && o.status !== 'sample_collected' && <div className="mt-3 text-xs bg-muted/30 rounded-lg p-2"><p><strong>Result:</strong> {result.numeric_value !== null ? `${result.numeric_value}${result.unit ? ` ${result.unit}` : ''}` : (result.result_data?.value ?? '—')}</p>{result.reference_low !== null || result.reference_high !== null ? <p><strong>Reference:</strong> {result.reference_low ?? '—'} – {result.reference_high ?? '—'}{result.unit ? ` ${result.unit}` : ''}</p> : null}{result.interpretation && <p><strong>Interpretation:</strong> {result.interpretation}</p>}</div>}
            </div>); })}
          {orders.length === 0 && <p className="text-sm text-muted-foreground">No lab orders yet.</p>}</div></div>
      </div>
    </div>
  );
}
