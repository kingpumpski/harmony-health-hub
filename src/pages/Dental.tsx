import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Smile, Plus, RefreshCw } from 'lucide-react';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string }
interface DentalRec { id: string; patient_id: string; examination: string; treatment_plan: string; procedures_performed: string; created_at: string }

export default function Dental() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [records, setRecords] = useState<DentalRec[]>([]);
  const [pid, setPid] = useState('');
  const [exam, setExam] = useState('');
  const [plan, setPlan] = useState('');
  const [proc, setProc] = useState('');
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    const [{ data: pts }, { data: recs }] = await Promise.all([
      searchPatientDirectory('', 200).then(({ data }) => ({ data, error: null })),
      supabase.from('dental_records').select('id,patient_id,examination,treatment_plan,procedures_performed,created_at').order('created_at', { ascending: false }).limit(50),
    ]);
    setPatients(pts ?? []);
    setRecords(recs ?? []);
    setLoading(false);
  };
  useEffect(() => { void load(); }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return toast({ title: 'Select a patient', variant: 'destructive' });
    const { error } = await (supabase as any).rpc('create_dental_record', {
      _patient_id: pid,
      _examination: exam,
      _treatment_plan: plan,
      _procedures_performed: proc,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Dental record saved' });
    setPid(''); setExam(''); setPlan(''); setProc('');
    void load();
  };

  const todayCount = records.filter((record) => new Date(record.created_at).toDateString() === new Date().toDateString()).length;
  const completedPlans = records.filter((record) => Boolean(record.treatment_plan)).length;

  return (
    <OperationalWorklistShell
      icon={Smile}
      eyebrow="Patient Care · Dental"
      title="Dental Clinic"
      description="Document examinations, treatment plans and procedures in a focused dental care worklist."
      actions={(
        <button type="button" onClick={() => void load()} disabled={loading} className="btn-secondary inline-flex items-center gap-2" aria-label="Refresh dental records">
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" /> {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      )}
      counters={[
        { label: 'Recent records', value: records.length, tone: 'text-primary', surface: 'bg-primary/5' },
        { label: 'Today', value: todayCount, tone: 'text-info', surface: 'bg-info/5' },
        { label: 'Treatment plans', value: completedPlans, tone: 'text-success', surface: 'bg-success/5' },
        { label: 'Patients available', value: patients.length, tone: 'text-foreground' },
      ]}
      beforeList={(
        <section className="card-medical p-5">
          <div className="flex items-start gap-2 mb-4">
            <Plus className="w-4 h-4 text-primary mt-0.5" aria-hidden="true" />
            <div>
              <h2 className="font-semibold">New dental record</h2>
              <p className="text-xs text-muted-foreground mt-1">Record today's examination and care plan for the selected patient.</p>
            </div>
          </div>
          <form onSubmit={submit} className="grid gap-3 md:grid-cols-2">
            <div className="md:col-span-2">
              <label htmlFor="dental-patient" className="text-xs font-semibold block mb-1">Patient <span className="text-critical">*</span></label>
              <select id="dental-patient" value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full" required>
                <option value="">Select patient…</option>
                {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}
              </select>
            </div>
            <div>
              <label htmlFor="dental-exam" className="text-xs font-semibold block mb-1">Examination findings</label>
              <textarea id="dental-exam" value={exam} onChange={(e) => setExam(e.target.value)} placeholder="Occlusion, hygiene, decay, gingival status…" rows={4} className="input-medical w-full" />
            </div>
            <div>
              <label htmlFor="dental-plan" className="text-xs font-semibold block mb-1">Treatment plan</label>
              <textarea id="dental-plan" value={plan} onChange={(e) => setPlan(e.target.value)} placeholder="Planned dental care" rows={4} className="input-medical w-full" />
            </div>
            <div className="md:col-span-2">
              <label htmlFor="dental-procedures" className="text-xs font-semibold block mb-1">Procedures performed today</label>
              <textarea id="dental-procedures" value={proc} onChange={(e) => setProc(e.target.value)} placeholder="Procedures completed during this visit" rows={3} className="input-medical w-full" />
            </div>
            <div className="md:col-span-2 flex justify-end">
              <button type="submit" className="btn-primary inline-flex items-center gap-2"><Plus className="w-4 h-4" aria-hidden="true" /> Save record</button>
            </div>
          </form>
        </section>
      )}
      listTitle="Recent dental records"
      listDescription="Clinical dental documentation remains visible in chronological order."
      listMeta={`${records.length} record${records.length === 1 ? '' : 's'}`}
      loading={loading}
      empty={records.length === 0}
      emptyTitle="No dental records"
      emptyDescription="Create a dental record above when a patient is assessed."
    >
      {records.map((r) => {
        const p = patients.find(x => x.id === r.patient_id);
        return (
          <article key={r.id} className="p-4 sm:p-5">
            <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <h2 className="font-medium">{p ? `${p.first_name} ${p.last_name}` : 'Patient'}</h2>
                <p className="text-xs text-muted-foreground">{p?.patient_code ?? r.patient_id} · {new Date(r.created_at).toLocaleString()}</p>
              </div>
              {r.treatment_plan && <span className="rounded-full bg-success/10 text-success px-2.5 py-1 text-[10px] font-semibold shrink-0">Treatment plan</span>}
            </div>
            <div className="mt-3 grid gap-3 md:grid-cols-3">
              {r.examination && <section className="rounded-xl border border-border p-3"><p className="text-[10px] uppercase tracking-wide text-muted-foreground">Examination</p><p className="mt-1 text-sm whitespace-pre-wrap">{r.examination}</p></section>}
              {r.treatment_plan && <section className="rounded-xl border border-primary/20 bg-primary/5 p-3"><p className="text-[10px] uppercase tracking-wide text-muted-foreground">Treatment plan</p><p className="mt-1 text-sm whitespace-pre-wrap">{r.treatment_plan}</p></section>}
              {r.procedures_performed && <section className="rounded-xl border border-border p-3"><p className="text-[10px] uppercase tracking-wide text-muted-foreground">Procedures</p><p className="mt-1 text-sm whitespace-pre-wrap">{r.procedures_performed}</p></section>}
            </div>
          </article>
        );
      })}
    </OperationalWorklistShell>
  );

}
