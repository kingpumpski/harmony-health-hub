import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Baby, Plus, Activity, Calendar } from 'lucide-react';

interface Patient { id: string; first_name: string; last_name: string }
interface Cycle {
  id: string; patient_id: string; partner_name: string | null; cycle_type: string;
  cycle_number: number; start_date: string; expected_retrieval_date: string | null;
  expected_transfer_date: string | null; protocol: string | null; status: string; outcome: string | null; notes: string | null;
}
interface Monitoring {
  id: string; cycle_id: string; visit_date: string; cycle_day: number | null;
  estradiol: number | null; lh: number | null; fsh: number | null; progesterone: number | null;
  follicle_count_left: number | null; follicle_count_right: number | null;
  endometrial_thickness: number | null; medication_adjustments: string | null; notes: string | null;
}

export default function Fertility() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [cycles, setCycles] = useState<Cycle[]>([]);
  const [selected, setSelected] = useState<Cycle | null>(null);
  const [monitoring, setMonitoring] = useState<Monitoring[]>([]);

  // new cycle
  const [pid, setPid] = useState('');
  const [partner, setPartner] = useState('');
  const [type, setType] = useState('IVF');
  const [startDate, setStartDate] = useState(new Date().toISOString().slice(0, 10));
  const [protocol, setProtocol] = useState('');

  // monitoring entry
  const [visitDate, setVisitDate] = useState(new Date().toISOString().slice(0, 10));
  const [cycleDay, setCycleDay] = useState<number>(1);
  const [estradiol, setEstradiol] = useState<number | ''>('');
  const [lh, setLh] = useState<number | ''>('');
  const [fsh, setFsh] = useState<number | ''>('');
  const [prog, setProg] = useState<number | ''>('');
  const [follL, setFollL] = useState<number | ''>('');
  const [follR, setFollR] = useState<number | ''>('');
  const [endo, setEndo] = useState<number | ''>('');
  const [meds, setMeds] = useState('');

  const loadAll = async () => {
    const [{ data: pts }, { data: cs }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name').limit(200),
      supabase.from('fertility_cycles').select('*').order('created_at', { ascending: false }),
    ]);
    setPatients(pts ?? []);
    setCycles(cs ?? []);
  };
  const loadMonitoring = async (cycleId: string) => {
    const { data } = await supabase.from('fertility_monitoring').select('*').eq('cycle_id', cycleId).order('visit_date', { ascending: false });
    setMonitoring(data ?? []);
  };

  useEffect(() => { loadAll(); }, []);
  useEffect(() => { if (selected) loadMonitoring(selected.id); }, [selected]);

  const createCycle = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return;
    const { data, error } = await supabase.from('fertility_cycles').insert({
      patient_id: pid, partner_name: partner || null, cycle_type: type,
      start_date: startDate, protocol: protocol || null, assigned_specialist: user?.id,
    }).select().single();
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Fertility cycle started' });
    setPid(''); setPartner(''); setProtocol('');
    setSelected(data as Cycle);
    loadAll();
  };

  const addMonitoring = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selected) return;
    const { error } = await supabase.from('fertility_monitoring').insert({
      cycle_id: selected.id, visit_date: visitDate, cycle_day: cycleDay,
      estradiol: estradiol === '' ? null : estradiol, lh: lh === '' ? null : lh,
      fsh: fsh === '' ? null : fsh, progesterone: prog === '' ? null : prog,
      follicle_count_left: follL === '' ? null : follL, follicle_count_right: follR === '' ? null : follR,
      endometrial_thickness: endo === '' ? null : endo, medication_adjustments: meds || null, recorded_by: user?.id,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Monitoring recorded' });
    setEstradiol(''); setLh(''); setFsh(''); setProg(''); setFollL(''); setFollR(''); setEndo(''); setMeds('');
    loadMonitoring(selected.id);
  };

  const updateOutcome = async (status: string, outcome: string) => {
    if (!selected) return;
    await supabase.from('fertility_cycles').update({ status, outcome }).eq('id', selected.id);
    setSelected({ ...selected, status, outcome });
    loadAll();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
          <Baby className="w-6 h-6 text-fertility" /> Fertility Clinic
        </h1>
        <p className="text-muted-foreground">IVF, IUI, ICSI, and FET cycles with monitoring.</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[360px_1fr]">
        <div className="space-y-4">
          <form onSubmit={createCycle} className="card-medical p-5 space-y-3">
            <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New Cycle</h2>
            <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full">
              <option value="">Select patient…</option>
              {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
            </select>
            <input value={partner} onChange={(e) => setPartner(e.target.value)} className="input-medical w-full" placeholder="Partner name (optional)" />
            <select value={type} onChange={(e) => setType(e.target.value)} className="input-medical w-full">
              <option value="IVF">IVF</option>
              <option value="IUI">IUI</option>
              <option value="ICSI">ICSI</option>
              <option value="FET">Frozen Embryo Transfer</option>
            </select>
            <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} className="input-medical w-full" />
            <input value={protocol} onChange={(e) => setProtocol(e.target.value)} className="input-medical w-full" placeholder="Protocol (e.g. Long agonist)" />
            <button className="btn-primary w-full">Start Cycle</button>
          </form>

          <div className="card-medical p-5">
            <h2 className="font-semibold mb-3">Active Cycles</h2>
            <div className="space-y-2 max-h-[480px] overflow-auto">
              {cycles.map((c) => {
                const p = patients.find((x) => x.id === c.patient_id);
                return (
                  <button key={c.id} onClick={() => setSelected(c)}
                    className={`w-full text-left rounded-xl border p-3 ${selected?.id === c.id ? 'border-fertility bg-fertility/5' : 'border-border hover:bg-accent/40'}`}>
                    <div className="flex justify-between">
                      <div>
                        <p className="font-medium text-sm">{p ? `${p.first_name} ${p.last_name}` : '—'}</p>
                        <p className="text-xs text-muted-foreground">{c.cycle_type} #{c.cycle_number} · {c.start_date}</p>
                      </div>
                      <span className={`text-xs px-2 py-0.5 rounded-full ${c.status === 'successful' ? 'bg-success/15 text-success' : c.status === 'unsuccessful' ? 'bg-critical/15 text-critical' : 'bg-fertility/15 text-fertility'}`}>{c.status}</span>
                    </div>
                  </button>
                );
              })}
              {cycles.length === 0 && <p className="text-sm text-muted-foreground">No cycles yet.</p>}
            </div>
          </div>
        </div>

        <div className="card-medical p-6 min-h-[400px]">
          {!selected ? (
            <div className="h-full flex items-center justify-center text-muted-foreground">
              Select or create a cycle.
            </div>
          ) : (
            <div className="space-y-6">
              <div className="flex justify-between items-start">
                <div>
                  <h2 className="text-lg font-semibold flex items-center gap-2"><Calendar className="w-5 h-5" /> {selected.cycle_type} Cycle</h2>
                  <p className="text-sm text-muted-foreground">Started {selected.start_date} · Protocol: {selected.protocol || '—'}</p>
                </div>
                <div className="flex gap-2">
                  <button onClick={() => updateOutcome('successful', 'positive')} className="btn-ghost text-xs text-success">Mark successful</button>
                  <button onClick={() => updateOutcome('unsuccessful', 'negative')} className="btn-ghost text-xs text-critical">Mark unsuccessful</button>
                </div>
              </div>

              <section>
                <h3 className="font-semibold mb-2 flex items-center gap-2"><Activity className="w-4 h-4" /> Add Monitoring Visit</h3>
                <form onSubmit={addMonitoring} className="grid grid-cols-2 md:grid-cols-4 gap-2">
                  <input type="date" value={visitDate} onChange={(e) => setVisitDate(e.target.value)} className="input-medical" />
                  <input type="number" value={cycleDay} onChange={(e) => setCycleDay(Number(e.target.value))} className="input-medical" placeholder="Cycle day" />
                  <input type="number" step="0.01" value={estradiol} onChange={(e) => setEstradiol(e.target.value === '' ? '' : Number(e.target.value))} className="input-medical" placeholder="Estradiol (pg/mL)" />
                  <input type="number" step="0.01" value={lh} onChange={(e) => setLh(e.target.value === '' ? '' : Number(e.target.value))} className="input-medical" placeholder="LH" />
                  <input type="number" step="0.01" value={fsh} onChange={(e) => setFsh(e.target.value === '' ? '' : Number(e.target.value))} className="input-medical" placeholder="FSH" />
                  <input type="number" step="0.01" value={prog} onChange={(e) => setProg(e.target.value === '' ? '' : Number(e.target.value))} className="input-medical" placeholder="Progesterone" />
                  <input type="number" value={follL} onChange={(e) => setFollL(e.target.value === '' ? '' : Number(e.target.value))} className="input-medical" placeholder="Follicles L" />
                  <input type="number" value={follR} onChange={(e) => setFollR(e.target.value === '' ? '' : Number(e.target.value))} className="input-medical" placeholder="Follicles R" />
                  <input type="number" step="0.1" value={endo} onChange={(e) => setEndo(e.target.value === '' ? '' : Number(e.target.value))} className="input-medical" placeholder="Endometrium (mm)" />
                  <input value={meds} onChange={(e) => setMeds(e.target.value)} className="input-medical md:col-span-2" placeholder="Medication adjustments" />
                  <button className="btn-primary col-span-2 md:col-span-4">Record visit</button>
                </form>
              </section>

              <section>
                <h3 className="font-semibold mb-2">Monitoring History</h3>
                <div className="overflow-auto">
                  <table className="w-full text-xs">
                    <thead className="text-muted-foreground"><tr>
                      <th className="text-left">Date</th><th>Day</th><th>E2</th><th>LH</th><th>FSH</th><th>Prog</th><th>Foll L/R</th><th>Endo</th>
                    </tr></thead>
                    <tbody>
                      {monitoring.map((m) => (
                        <tr key={m.id} className="border-t border-border">
                          <td className="py-2">{m.visit_date}</td>
                          <td className="text-center">{m.cycle_day ?? '—'}</td>
                          <td className="text-center">{m.estradiol ?? '—'}</td>
                          <td className="text-center">{m.lh ?? '—'}</td>
                          <td className="text-center">{m.fsh ?? '—'}</td>
                          <td className="text-center">{m.progesterone ?? '—'}</td>
                          <td className="text-center">{m.follicle_count_left ?? '—'}/{m.follicle_count_right ?? '—'}</td>
                          <td className="text-center">{m.endometrial_thickness ?? '—'}mm</td>
                        </tr>
                      ))}
                      {monitoring.length === 0 && <tr><td colSpan={8} className="text-center py-3 text-muted-foreground">No visits yet.</td></tr>}
                    </tbody>
                  </table>
                </div>
              </section>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
