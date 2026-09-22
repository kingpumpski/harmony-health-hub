import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Smile, Plus } from 'lucide-react';

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

  const load = async () => {
    const [{ data: pts }, { data: recs }] = await Promise.all([
      searchPatientDirectory('', 200).then(({ data }) => ({ data, error: null })),
      supabase.from('dental_records').select('id,patient_id,examination,treatment_plan,procedures_performed,created_at').order('created_at', { ascending: false }).limit(50),
    ]);
    setPatients(pts ?? []);
    setRecords(recs ?? []);
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

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Smile className="w-6 h-6 text-primary" /> Dental Clinic</h1>
        <p className="text-muted-foreground">Examinations, treatment plans, and procedures.</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[400px_1fr]">
        <form onSubmit={submit} className="card-medical p-5 space-y-3 h-fit">
          <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New Dental Record</h2>
          <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full">
            <option value="">Select patient…</option>
            {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
          </select>
          <textarea value={exam} onChange={(e) => setExam(e.target.value)} placeholder="Examination findings (occlusion, hygiene, decay, gingival status…)" rows={3} className="input-medical w-full" />
          <textarea value={plan} onChange={(e) => setPlan(e.target.value)} placeholder="Treatment plan" rows={2} className="input-medical w-full" />
          <textarea value={proc} onChange={(e) => setProc(e.target.value)} placeholder="Procedures performed today" rows={2} className="input-medical w-full" />
          <button className="btn-primary w-full">Save record</button>
        </form>

        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Recent dental records</h2>
          <div className="space-y-3 max-h-[600px] overflow-auto">
            {records.map((r) => {
              const p = patients.find(x => x.id === r.patient_id);
              return (
                <div key={r.id} className="rounded-xl border border-border p-4">
                  <div className="flex justify-between text-sm mb-2">
                    <span className="font-medium">{p ? `${p.first_name} ${p.last_name}` : 'Patient'}</span>
                    <span className="text-muted-foreground">{new Date(r.created_at).toLocaleDateString()}</span>
                  </div>
                  {r.examination && <p className="text-xs"><strong>Exam:</strong> {r.examination}</p>}
                  {r.treatment_plan && <p className="text-xs"><strong>Plan:</strong> {r.treatment_plan}</p>}
                  {r.procedures_performed && <p className="text-xs"><strong>Procedures:</strong> {r.procedures_performed}</p>}
                </div>
              );
            })}
            {records.length === 0 && <p className="text-sm text-muted-foreground">No records yet.</p>}
          </div>
        </div>
      </div>
    </div>
  );
}
