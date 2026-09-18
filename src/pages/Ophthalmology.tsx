import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useEffect, useState } from 'react';
import { Eye, FileUp, ShieldCheck, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string }
interface Exam { id: string; patient_id: string; visual_acuity: string | null; refraction: string | null; keratometry: string | null; intraocular_pressure: number | null; color_vision: string | null; fundus_notes: string | null; status: string; created_at: string }

export default function Ophthalmology() {
  const [patients, setPatients] = useState<Patient[]>([]);
  const [exams, setExams] = useState<Exam[]>([]);
  const [patientId, setPatientId] = useState('');
  const [form, setForm] = useState({ visualAcuity: '', refraction: '', keratometry: '', intraocularPressure: '', colorVision: 'Normal', fundusNotes: '' });
  const [saving, setSaving] = useState(false);

  const load = async () => {
    const [{ data: pts, error: pError }, { data: rows, error: eError }] = await Promise.all([
      searchPatientDirectory('', 200).then(({ data }) => ({ data, error: null })),
      supabase.from('ophthalmology_exams').select('*').order('created_at', { ascending: false }).limit(50),
    ]);
    if (pError || eError) return toast({ title: 'Unable to load ophthalmology workspace', description: pError?.message ?? eError?.message, variant: 'destructive' });
    setPatients(pts ?? []); setExams((rows ?? []) as Exam[]);
  };
  useEffect(() => { void load(); }, []);

  const save = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!patientId) return toast({ title: 'Select a patient', variant: 'destructive' });
    setSaving(true);
    try {
      const { error } = await (supabase as any).rpc('create_ophthalmology_exam', {
        _patient_id: patientId,
        _visual_acuity: form.visualAcuity,
        _refraction: form.refraction,
        _keratometry: form.keratometry,
        _intraocular_pressure: form.intraocularPressure === '' ? null : Number(form.intraocularPressure),
        _color_vision: form.colorVision,
        _fundus_notes: form.fundusNotes,
      });
      if (error) throw error;
      toast({ title: 'Ophthalmology exam saved' });
      setPatientId('');
      setForm({ visualAcuity: '', refraction: '', keratometry: '', intraocularPressure: '', colorVision: 'Normal', fundusNotes: '' });
      void load();
    } catch (error: any) {
      toast({ title: 'Unable to save exam', description: error.message, variant: 'destructive' });
    } finally { setSaving(false); }
  };

  return <div className="space-y-6 animate-fade-in">
    <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Eye className="w-6 h-6 text-primary" /> Ophthalmology</h1><p className="text-muted-foreground">Clinician-recorded eye examinations with an auditable review workflow.</p></div>

    <div className="rounded-xl border border-info/30 bg-info/5 p-3 text-sm flex items-start gap-2"><AlertCircle className="w-4 h-4 text-info mt-0.5" /><span>No diagnosis is fabricated by the interface. AI assistance can be attached later as a separately identified clinical advisory with provenance and clinician review.</span></div>

    <div className="grid gap-6 xl:grid-cols-[minmax(280px,400px)_1fr]">
      <form onSubmit={save} className="card-medical p-5 space-y-4">
        <h2 className="font-semibold">New eye examination</h2>
        <select required value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}</select>
        <input placeholder="Visual acuity" value={form.visualAcuity} onChange={(e) => setForm({ ...form, visualAcuity: e.target.value })} className="input-medical w-full" />
        <input placeholder="Refraction" value={form.refraction} onChange={(e) => setForm({ ...form, refraction: e.target.value })} className="input-medical w-full" />
        <input placeholder="Keratometry" value={form.keratometry} onChange={(e) => setForm({ ...form, keratometry: e.target.value })} className="input-medical w-full" />
        <label className="block text-sm"><span className="font-medium">Intraocular pressure (mmHg)</span><input min="0" type="number" step="0.1" value={form.intraocularPressure} onChange={(e) => setForm({ ...form, intraocularPressure: e.target.value })} className="input-medical mt-1 w-full" /></label>
        <select value={form.colorVision} onChange={(e) => setForm({ ...form, colorVision: e.target.value })} className="input-medical w-full"><option>Normal</option><option>Deficient</option><option>Unable to complete</option></select>
        <textarea rows={4} placeholder="Fundoscopy / examination notes" value={form.fundusNotes} onChange={(e) => setForm({ ...form, fundusNotes: e.target.value })} className="textarea-medical w-full" />
        <button disabled={saving} className="btn-primary w-full inline-flex items-center justify-center gap-2"><FileUp className="w-4 h-4" />{saving ? 'Saving…' : 'Save examination'}</button>
      </form>

      <section className="card-medical p-5"><div className="flex items-center justify-between mb-4"><div><h2 className="font-semibold">Recent examinations</h2><p className="text-sm text-muted-foreground">Clinical measurements and review status.</p></div><ShieldCheck className="w-5 h-5 text-success" /></div><div className="space-y-3">{exams.map((exam) => { const p = patients.find((x) => x.id === exam.patient_id); return <article key={exam.id} className="rounded-xl border border-border p-4"><div className="flex flex-col gap-1 sm:flex-row sm:justify-between"><p className="font-medium">{p ? `${p.first_name} ${p.last_name}` : 'Patient'}</p><span className="text-xs capitalize text-muted-foreground">{exam.status}</span></div><p className="mt-2 text-xs text-muted-foreground">{new Date(exam.created_at).toLocaleString()}</p><div className="mt-3 grid gap-2 sm:grid-cols-2 text-sm"><span>VA: {exam.visual_acuity || '—'}</span><span>IOP: {exam.intraocular_pressure ?? '—'}</span><span>Refraction: {exam.refraction || '—'}</span><span>Keratometry: {exam.keratometry || '—'}</span></div>{exam.fundus_notes && <p className="mt-3 text-sm">{exam.fundus_notes}</p>}</article>; })}{exams.length === 0 && <p className="text-sm text-muted-foreground">No examinations recorded yet.</p>}</div></section>
    </div>
  </div>;
}
