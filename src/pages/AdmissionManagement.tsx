import { FormEvent, useCallback, useEffect, useState } from 'react';
import { BedDouble, LogOut, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string }
interface Admission { id: string; patient_id: string; admitted_at: string; discharged_at: string | null; ward: string | null; bed: string | null; reason: string | null; status: string; discharge_summary: string | null }
const db = supabase as any;

export default function AdmissionManagement() {
  const [patients, setPatients] = useState<Patient[]>([]);
  const [rows, setRows] = useState<Admission[]>([]);
  const [patientId, setPatientId] = useState('');
  const [ward, setWard] = useState('');
  const [bed, setBed] = useState('');
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    const [{ data: p, error: pe }, { data: a, error: ae }] = await Promise.all([
      db.from('patients').select('id, first_name, last_name, patient_code').limit(300),
      db.from('admissions').select('*').order('admitted_at', { ascending: false }).limit(200),
    ]);
    if (pe || ae) { toast.error((pe ?? ae)?.message ?? 'Unable to load admissions'); return; }
    setPatients(p ?? []); setRows(a ?? []);
  }, []);
  useEffect(() => { void load(); }, [load]);

  const admit = async (event: FormEvent) => {
    event.preventDefault();
    if (!patientId || !ward || !reason) { toast.error('Patient, ward and admission reason are required.'); return; }
    setSaving(true);
    const { error } = await db.rpc('create_admission_workflow', { _patient_id: patientId, _ward: ward, _bed: bed || null, _reason: reason });
    setSaving(false);
    if (error) { toast.error(error.message); return; }
    setPatientId(''); setWard(''); setBed(''); setReason('');
    toast.success('Patient admitted'); void load();
  };

  const discharge = async (id: string) => {
    const { error } = await db.rpc('discharge_admission_workflow', { _admission_id: id, _summary: 'Discharged from inpatient admission.' });
    if (error) toast.error(error.message); else { toast.success('Admission discharged'); void load(); }
  };

  const patientName = (id: string) => { const p = patients.find((item) => item.id === id); return p ? `${p.first_name} ${p.last_name} · ${p.patient_code}` : 'Unknown patient'; };

  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><BedDouble className="w-6 h-6 text-primary" /> Admissions & Inpatient Flow</h1><p className="text-muted-foreground">Admission, ward/bed allocation and discharge workflow.</p></div><button onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="w-4 h-4" /> Refresh</button></div>
    <div className="grid gap-6 lg:grid-cols-[380px_1fr]">
      <form onSubmit={admit} className="card-medical p-5 space-y-3 h-fit"><h2 className="font-semibold">New admission</h2><select required value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}</select><input required value={ward} onChange={(e) => setWard(e.target.value)} className="input-medical w-full" placeholder="Ward" /><input value={bed} onChange={(e) => setBed(e.target.value)} className="input-medical w-full" placeholder="Bed" /><textarea required value={reason} onChange={(e) => setReason(e.target.value)} className="input-medical w-full" rows={3} placeholder="Admission reason / clinical indication" /><button disabled={saving} className="btn-primary w-full">{saving ? 'Admitting…' : 'Admit patient'}</button></form>
      <div className="card-medical p-5"><h2 className="font-semibold mb-3">Admission history</h2><div className="space-y-3">{rows.map((row) => <article key={row.id} className="rounded-xl border border-border p-4"><div className="flex flex-wrap justify-between gap-2"><div><p className="font-medium">{patientName(row.patient_id)}</p><p className="text-xs text-muted-foreground">{row.ward ?? '—'} · Bed {row.bed ?? '—'} · {new Date(row.admitted_at).toLocaleString()}</p></div><span className="text-xs rounded-full bg-muted px-2 py-1 capitalize">{row.status}</span></div>{row.reason && <p className="mt-2 text-sm">{row.reason}</p>}{row.status === 'admitted' && <button onClick={() => void discharge(row.id)} className="btn-ghost text-xs mt-3 inline-flex items-center gap-1"><LogOut className="w-3 h-3" /> Discharge</button>}{row.discharged_at && <p className="mt-2 text-xs text-muted-foreground">Discharged: {new Date(row.discharged_at).toLocaleString()}</p>}{row.discharge_summary && <p className="mt-1 text-xs text-muted-foreground">{row.discharge_summary}</p>}</article>)}{rows.length === 0 && <p className="text-sm text-muted-foreground">No admissions recorded.</p>}</div></div>
    </div>
  </div>;
}
