import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useEffect, useState } from 'react';
import { Activity, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Patient { id: string; patient_code: string; first_name: string; last_name: string }
interface Vital { id: string; patient_id: string; systolic: number | null; diastolic: number | null; heart_rate: number | null; temperature: number | null; oxygen_saturation: number | null; recorded_at: string }

export default function Monitoring() {
  const [patients, setPatients] = useState<Patient[]>([]);
  const [patientId, setPatientId] = useState('');
  const [vitals, setVitals] = useState<Vital[]>([]);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    const query = supabase.from('vital_signs').select('id, patient_id, systolic, diastolic, heart_rate, temperature, oxygen_saturation, recorded_at').order('recorded_at', { ascending: false }).limit(100);
    const { data, error } = patientId ? await query.eq('patient_id', patientId) : await query;
    if (error) toast.error(error.message); else setVitals((data ?? []) as Vital[]);
    setLoading(false);
  };

  useEffect(() => { void searchPatientDirectory('', 300).then(({ data, error }) => ({ data, error })).then(({ data, error }) => { if (error) toast.error(error.message); else setPatients((data ?? []) as Patient[]); }); }, []);
  useEffect(() => { void load(); }, [patientId]);

  const names = new Map(patients.map((p) => [p.id, `${p.first_name} ${p.last_name}`]));
  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Activity className="w-6 h-6 text-primary" /> Clinical Monitoring</h1><p className="text-muted-foreground">Review recent vital-sign observations and identify patients needing attention.</p></div><button onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="w-4 h-4" /> Refresh</button></div>
    <div className="card-medical p-4"><select value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full"><option value="">All patients</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} ({p.patient_code})</option>)}</select></div>
    <div className="card-medical overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-3">Patient</th><th className="p-3">BP</th><th className="p-3">HR</th><th className="p-3">Temp</th><th className="p-3">SpO₂</th><th className="p-3">Recorded</th></tr></thead><tbody>{vitals.map((v) => <tr key={v.id} className="border-b last:border-0"><td className="p-3 font-medium">{names.get(v.patient_id) ?? v.patient_id}</td><td className="p-3">{v.systolic ?? '—'}/{v.diastolic ?? '—'}</td><td className="p-3">{v.heart_rate ?? '—'}</td><td className="p-3">{v.temperature ?? '—'}</td><td className="p-3">{v.oxygen_saturation != null ? `${v.oxygen_saturation}%` : '—'}</td><td className="p-3 text-muted-foreground">{new Date(v.recorded_at).toLocaleString()}</td></tr>)}</tbody></table>{!loading && vitals.length === 0 && <p className="p-6 text-sm text-muted-foreground">No vital observations found.</p>}{loading && <p className="p-6 text-sm text-muted-foreground">Loading observations…</p>}</div>
  </div>;
}
