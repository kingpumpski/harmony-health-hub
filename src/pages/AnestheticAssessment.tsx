import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { ShieldCheck, Plus } from 'lucide-react';

interface Patient { id: string; first_name: string; last_name: string }

export default function AnestheticAssessment() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [records, setRecords] = useState<any[]>([]);
  const [pid, setPid] = useState('');
  const [asa, setAsa] = useState('I');
  const [airway, setAirway] = useState('');
  const [cv, setCv] = useState('');
  const [resp, setResp] = useState('');
  const [allergies, setAllergies] = useState('');
  const [meds, setMeds] = useState('');
  const [fasting, setFasting] = useState('');
  const [conclusion, setConclusion] = useState('');
  const [cleared, setCleared] = useState(false);

  useEffect(() => {
    supabase.from('patients').select('id, first_name, last_name').limit(200).then(({ data }) => setPatients(data ?? []));
    supabase.from('anesthetic_assessments').select('*').order('created_at', { ascending: false }).limit(50).then(({ data }) => setRecords(data ?? []));
  }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return;
    const { error } = await supabase.from('anesthetic_assessments').insert({
      patient_id: pid, asa_class: asa, airway_assessment: airway, cardiovascular: cv, respiratory: resp,
      allergies, medications: meds, fasting_status: fasting, conclusions: conclusion,
      cleared_for_procedure: cleared, cleared_by: cleared ? user?.id : null, status: 'completed',
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: cleared ? 'Patient cleared for procedure' : 'Assessment saved' });
    setPid(''); setAirway(''); setCv(''); setResp(''); setAllergies(''); setMeds(''); setFasting(''); setConclusion(''); setCleared(false); setAsa('I');
    supabase.from('anesthetic_assessments').select('*').order('created_at', { ascending: false }).limit(50).then(({ data }) => setRecords(data ?? []));
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><ShieldCheck className="w-6 h-6 text-primary" /> Anesthetic Assessment</h1>
        <p className="text-muted-foreground">Pre-procedure clearance questionnaire and findings.</p>
      </div>

      <form onSubmit={submit} className="card-medical p-6 space-y-3">
        <div className="grid md:grid-cols-2 gap-3">
          <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical">
            <option value="">Select patient…</option>
            {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
          </select>
          <select value={asa} onChange={(e) => setAsa(e.target.value)} className="input-medical">
            <option>I — Healthy</option>
            <option>II — Mild systemic disease</option>
            <option>III — Severe systemic disease</option>
            <option>IV — Severe systemic disease, threat to life</option>
            <option>V — Moribund</option>
          </select>
        </div>
        <div className="grid md:grid-cols-2 gap-3">
          <textarea value={airway} onChange={(e) => setAirway(e.target.value)} rows={2} placeholder="Airway assessment (Mallampati, neck mobility, mouth opening)" className="input-medical" />
          <textarea value={cv} onChange={(e) => setCv(e.target.value)} rows={2} placeholder="Cardiovascular (BP trend, ECG, exercise tolerance)" className="input-medical" />
          <textarea value={resp} onChange={(e) => setResp(e.target.value)} rows={2} placeholder="Respiratory (asthma, COPD, OSA)" className="input-medical" />
          <textarea value={allergies} onChange={(e) => setAllergies(e.target.value)} rows={2} placeholder="Allergies" className="input-medical" />
          <textarea value={meds} onChange={(e) => setMeds(e.target.value)} rows={2} placeholder="Current medications" className="input-medical" />
          <input value={fasting} onChange={(e) => setFasting(e.target.value)} placeholder="Fasting status (e.g. NPO since 22:00)" className="input-medical" />
        </div>
        <textarea value={conclusion} onChange={(e) => setConclusion(e.target.value)} rows={3} placeholder="Conclusions and recommendations" className="input-medical w-full" />
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={cleared} onChange={(e) => setCleared(e.target.checked)} />
          Patient is cleared for the planned procedure
        </label>
        <button className="btn-primary"><Plus className="w-4 h-4 mr-2" /> Submit assessment</button>
      </form>

      <div className="card-medical p-5">
        <h2 className="font-semibold mb-3">Recent assessments</h2>
        <div className="space-y-2">
          {records.map((r) => (
            <div key={r.id} className="rounded-xl border border-border p-3 text-sm flex justify-between">
              <span>ASA {r.asa_class} · {r.cleared_for_procedure ? <span className="text-success">Cleared</span> : <span className="text-warning">Pending</span>}</span>
              <span className="text-muted-foreground">{new Date(r.created_at).toLocaleDateString()}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
