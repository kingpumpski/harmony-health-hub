import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { FlaskConical, Plus, CheckCircle2, ShieldCheck, AlertTriangle, LockKeyhole } from 'lucide-react';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string; email: string | null }
interface LabOrder {
  id: string; patient_id: string; test_name: string; test_category: string | null;
  priority: string; status: string; created_at: string; clinical_notes: string | null;
}
interface LabResult {
  id: string; lab_order_id: string; result_data: { value?: string } | null; interpretation: string | null;
  is_abnormal: boolean; status: string; entered_at: string; approved_at: string | null;
}
interface CreateLabOrderResponse {
  lab_order_id: string;
  service_order_id: string;
  status: string;
}

export default function Laboratory() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [orders, setOrders] = useState<LabOrder[]>([]);
  const [resultsByOrder, setResultsByOrder] = useState<Record<string, LabResult>>({});

  const [pid, setPid] = useState('');
  const [testName, setTestName] = useState('');
  const [category, setCategory] = useState('');
  const [priority, setPriority] = useState('routine');
  const [notes, setNotes] = useState('');
  const [amount, setAmount] = useState('');

  const [resultFor, setResultFor] = useState<string | null>(null);
  const [resultText, setResultText] = useState('');
  const [interpretation, setInterpretation] = useState('');
  const [isAbnormal, setIsAbnormal] = useState(false);

  const loadAll = async () => {
    const [{ data: pts }, { data: ord }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name, patient_code, email').limit(200),
      supabase.from('lab_orders').select('*').order('created_at', { ascending: false }).limit(50),
    ]);
    setPatients(pts ?? []);
    setOrders(ord ?? []);
    if (ord && ord.length) {
      const { data: res } = await supabase.from('lab_results').select('*').in('lab_order_id', ord.map((o) => o.id));
      const map: Record<string, LabResult> = {};
      (res ?? []).forEach((r) => (map[r.lab_order_id] = r as LabResult));
      setResultsByOrder(map);
    }
  };

  useEffect(() => { void loadAll(); }, []);

  const createOrder = async (e: React.FormEvent) => {
    e.preventDefault();
    const numericAmount = Number(amount);
    if (!pid || !testName || !Number.isFinite(numericAmount) || numericAmount < 0) {
      toast({ title: 'Complete the order details', description: 'Patient, test name and a valid amount are required.', variant: 'destructive' });
      return;
    }

    const { error } = await supabase.rpc('create_lab_order_with_payment_gate', {
      _patient_id: pid,
      _test_name: testName,
      _test_category: category || null,
      _priority: priority,
      _clinical_notes: notes || null,
      _amount: numericAmount,
    } as never);

    if (error) {
      toast({ title: 'Failed to create lab order', description: error.message, variant: 'destructive' });
      return;
    }

    setPid(''); setTestName(''); setCategory(''); setNotes(''); setPriority('routine'); setAmount('');
    toast({
      title: numericAmount > 0 ? 'Lab order sent to Accounts' : 'Lab order created',
      description: numericAmount > 0 ? 'The laboratory cannot begin until Accounts releases the order.' : 'The order is available to the laboratory workflow.',
    });
    void loadAll();
  };

  const collectSample = async (id: string) => {
    const order = orders.find((item) => item.id === id);
    if (!order) return;
    const { data: gate, error: gateError } = await supabase
      .from('service_orders')
      .select('status')
      .eq('related_entity_id', id)
      .eq('department', 'laboratory')
      .maybeSingle();

    if (gateError) {
      toast({ title: 'Could not verify payment gate', description: gateError.message, variant: 'destructive' });
      return;
    }
    if (gate && !['released', 'in_progress', 'completed'].includes(gate.status)) {
      toast({ title: 'Payment approval required', description: 'Accounts must release this laboratory order before sample collection.', variant: 'destructive' });
      return;
    }

    const { error } = await supabase.from('lab_orders').update({
      status: 'sample_collected', collected_by: user?.id, sample_collected_at: new Date().toISOString(),
    }).eq('id', id);
    if (error) toast({ title: 'Could not collect sample', description: error.message, variant: 'destructive' });
    else void loadAll();
  };

  const submitResult = async (orderId: string) => {
    const { error } = await supabase.from('lab_results').insert({
      lab_order_id: orderId, result_data: { value: resultText },
      interpretation, is_abnormal: isAbnormal, entered_by: user?.id, status: 'completed',
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    await supabase.from('lab_orders').update({ status: 'completed' }).eq('id', orderId);
    setResultFor(null); setResultText(''); setInterpretation(''); setIsAbnormal(false);
    toast({ title: 'Result submitted', description: 'Pending approval.' });
    void loadAll();
  };

  const approveResult = async (resultId: string, orderId: string, patientId: string) => {
    await supabase.from('lab_results').update({
      status: 'approved', approved_by: user?.id, approved_at: new Date().toISOString(),
    }).eq('id', resultId);
    await supabase.from('lab_orders').update({ status: 'approved' }).eq('id', orderId);

    const patient = patients.find((p) => p.id === patientId);
    if (patient?.email) {
      try {
        await supabase.functions.invoke('notify-lab-result', {
          body: {
            patientEmail: patient.email,
            patientName: `${patient.first_name} ${patient.last_name}`,
            testName: orders.find((o) => o.id === orderId)?.test_name ?? 'Lab Test',
          },
        });
      } catch (e) {
        console.warn('Email notification failed', e);
      }
    }

    toast({ title: 'Result approved', description: 'Patient notified by email if available.' });
    void loadAll();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
          <FlaskConical className="w-6 h-6 text-primary" /> Laboratory
        </h1>
        <p className="text-muted-foreground">Test ordering → payment approval → sample → results → approval.</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[380px_1fr]">
        <form onSubmit={createOrder} className="card-medical p-5 space-y-3 h-fit">
          <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New Lab Order</h2>
          <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full">
            <option value="">Select patient…</option>
            {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
          </select>
          <input value={testName} onChange={(e) => setTestName(e.target.value)} className="input-medical w-full" placeholder="Test name (e.g. Full Blood Count)" />
          <input value={category} onChange={(e) => setCategory(e.target.value)} className="input-medical w-full" placeholder="Category (Hematology, Chemistry, …)" />
          <select value={priority} onChange={(e) => setPriority(e.target.value)} className="input-medical w-full">
            <option value="routine">Routine</option><option value="urgent">Urgent</option><option value="stat">STAT</option>
          </select>
          <input value={amount} onChange={(e) => setAmount(e.target.value)} className="input-medical w-full" inputMode="decimal" min="0" step="0.01" type="number" placeholder="Charge (GHS)" />
          <textarea value={notes} onChange={(e) => setNotes(e.target.value)} className="input-medical w-full" rows={2} placeholder="Clinical notes" />
          <button className="btn-primary w-full">Order Test</button>
          <p className="text-xs text-muted-foreground flex items-start gap-2"><LockKeyhole className="w-3.5 h-3.5 mt-0.5" /> Chargeable tests are blocked until Accounts releases them.</p>
        </form>

        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Lab Queue</h2>
          <div className="space-y-3">
            {orders.map((o) => {
              const p = patients.find((x) => x.id === o.patient_id);
              const result = resultsByOrder[o.id];
              return (
                <div key={o.id} className="rounded-xl border border-border p-4">
                  <div className="flex justify-between items-start gap-3">
                    <div>
                      <p className="font-medium">{o.test_name}</p>
                      <p className="text-xs text-muted-foreground">{p ? `${p.first_name} ${p.last_name}` : '—'} · {o.test_category ?? '—'} · {o.priority.toUpperCase()}</p>
                    </div>
                    <span className={`text-xs px-2 py-0.5 rounded-full ${o.status === 'approved' ? 'bg-success/15 text-success' : o.status === 'completed' ? 'bg-info/15 text-info' : o.status === 'sample_collected' ? 'bg-warning/15 text-warning' : 'bg-muted text-muted-foreground'}`}>{o.status.replace('_', ' ')}</span>
                  </div>
                  {result?.is_abnormal && <div className="mt-2 flex items-center gap-2 text-critical text-xs"><AlertTriangle className="w-3 h-3" /> Abnormal result flagged</div>}
                  <div className="mt-3 flex flex-wrap gap-2">
                    {o.status === 'ordered' && <button onClick={() => void collectSample(o.id)} className="btn-ghost text-xs">Collect sample</button>}
                    {o.status === 'sample_collected' && <button onClick={() => setResultFor(o.id)} className="btn-primary text-xs">Enter result</button>}
                    {o.status === 'completed' && result && <button onClick={() => void approveResult(result.id, o.id, o.patient_id)} className="btn-primary text-xs inline-flex items-center gap-1"><ShieldCheck className="w-3 h-3" /> Approve & notify</button>}
                    {o.status === 'approved' && <span className="text-xs text-success inline-flex items-center gap-1"><CheckCircle2 className="w-3 h-3" /> Approved</span>}
                  </div>
                  {resultFor === o.id && (
                    <div className="mt-3 space-y-2 border-t pt-3">
                      <textarea value={resultText} onChange={(e) => setResultText(e.target.value)} className="input-medical w-full" rows={2} placeholder="Result values" />
                      <input value={interpretation} onChange={(e) => setInterpretation(e.target.value)} className="input-medical w-full" placeholder="Interpretation" />
                      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={isAbnormal} onChange={(e) => setIsAbnormal(e.target.checked)} /> Abnormal result</label>
                      <div className="flex gap-2"><button onClick={() => void submitResult(o.id)} className="btn-primary text-xs">Submit</button><button onClick={() => setResultFor(null)} className="btn-ghost text-xs">Cancel</button></div>
                    </div>
                  )}
                  {result && o.status !== 'sample_collected' && <div className="mt-3 text-xs bg-muted/30 rounded-lg p-2"><p><strong>Result:</strong> {result.result_data?.value ?? '—'}</p>{result.interpretation && <p><strong>Interpretation:</strong> {result.interpretation}</p>}</div>}
                </div>
              );
            })}
            {orders.length === 0 && <p className="text-sm text-muted-foreground">No lab orders yet.</p>}
          </div>
        </div>
      </div>
    </div>
  );
}
