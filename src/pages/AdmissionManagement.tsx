import { FormEvent, useEffect, useState } from 'react';
import { BedDouble, LogOut, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string }
interface Admission { id: string; patient_id: string; admitted_at: string; discharged_at: string | null; ward: string | null; bed: string | null; diagnosis: string | null; status: string; notes: string | null }

export default function AdmissionManagement() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [rows, setRows] = useState<Admission[]>([]);
  const [patientId, setPatientId] = useState('');
  const [ward, setWard] = useState('');
  const [bed, setBed] = useState('');
  const [diagnosis, setDiagnosis] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  const load = async () => {
    const [{ data: p, error: pe }, { data: a, error: ae }] = await Promise.all([
      (supabase as any).from('patients').select('id, first_name, last_name, patient_code').limit(300),
      (supabase as any).from('admissions').select('*').order('admitted_at', { ascending: false }).limit(200),
    ]);
    if (pe || ae) return toast.error((pe ?? ae)?.message ?? 'Unable to load admissions');
    setPatients(p ?? []); setRows(a ?? []);
  };
  useEffect(() => { void load(); }, []);

  const admit = async (event: FormEvent) => {
    event.preventDefault();
    if (!patientId || !ward) return toast.error('Patient and ward are required.');
    setSaving(true);
    const { error } = await (supabase as any).from('admissions').insert({ patient_id: patientId, ward, bed: bed || null, diagnosis: diagnosis || null, notes: notes || null, admitting_practitioner: user?.id, created_by: user?.id, status: 'admitted' });
    setSaving(false);
    if (error) return toast.error(error.message);
    setPatientId(''); setWard(''); setBed(''); setDiagnosis(''); setNotes('');
    toast.success('Patient admitted'); void load();
  };

  const discharge = async (id: string) => {
    const { error } = await (supabase as any).from('admissions').update({ status: 'discharged', discharged_at: new Date().toISOString() }).eq('id', id).eq('status', 'admitted');
    if (error) toast.error(error.message); else { toast.success('Admission discharged'); void load(); }
  };

  const patientName = (id: string) => { const p = patients.find((item) => item.id === id); return p ? `${p.first_name} ${p.last_name} · ${p.patient_code}` : 'Unknown patient'; };

  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><BedDouble className="w-6 h-6 text-primary" /> Admissions & Inpatient Flow</h1><p className="text-muted-foreground">Admission, ward/bed allocation and discharge workflow.</p></div><button onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="w-4 h-4" /> Refresh</button></div>
    <div className="grid gap-6 lg:grid-cols-[380px_1fr]">
      <form onSubmit={admit} className="card-medical p-5 space-y-3 h-fit"><h2 className="font-semibold">New admission</h2><select required value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}</select><input required value={ward} onChange={(e) => setWard(e.target.value)} className="input-medical w-full" placeholder="Ward" /><input value={bed} onChange={(e) => setBed(e.target.value)} className="input-medical w-full" placeholder="Bed" /><input value={diagnosis} onChange={(e) => setDiagnosis(e.target.value)} className="input-medical w-full" placeholder="Admission diagnosis / reason" /><textarea value={notes} onChange={(e) => setNotes(e.target.value)} className="input-medical w-full" rows={3} placeholder="Admission notes" /><button disabled={saving} className="btn-primary w-full">{saving ? 'Admitting…' : 'Admit patient'}</button></form>
      <div className="card-medical p-5"><h2 className="font-semibold mb-3">Admission history</h2><div className="space-y-3">{rows.map((row) => <article key={row.id} className="rounded-xl border border-border p-4"><div className="flex flex-wrap justify-between gap-2"><div><p className="font-medium">{patientName(row.patient_id)}</p><p className="text-xs text-muted-foreground">{row.ward ?? '—'} · Bed {row.bed ?? '—'} · {new Date(row.admitted_at).toLocaleString()}</p></div><span className="text-xs rounded-full bg-muted px-2 py-1 capitalize">{row.status}</span></div>{row.diagnosis && <p className="mt-2 text-sm">{row.diagnosis}</p>}{row.status === 'admitted' && <button onClick={() => void discharge(row.id)} className="btn-ghost text-xs mt-3 inline-flex items-center gap-1"><LogOut className="w-3 h-3" /> Discharge</button>}</article>)}{rows.length === 0 && <p className="text-sm text-muted-foreground">No admissions recorded.</p>}</div></div>
    </div>
  </div>;
}
