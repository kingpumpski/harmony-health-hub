import { useEffect, useState } from 'react';
import { FileText, Plus, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

type Patient = { id: string; first_name: string; last_name: string; patient_code: string };
type NursingNote = {
  id: string; patient_id: string; note_type: string; note_text: string; assessment: string | null;
  intervention: string | null; evaluation: string | null; author_id: string; created_at: string;
};

export default function NursingNotes() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [notes, setNotes] = useState<NursingNote[]>([]);
  const [patientId, setPatientId] = useState('');
  const [noteType, setNoteType] = useState('progress');
  const [noteText, setNoteText] = useState('');
  const [assessment, setAssessment] = useState('');
  const [intervention, setIntervention] = useState('');
  const [evaluation, setEvaluation] = useState('');
  const [busy, setBusy] = useState(false);

  const load = async () => {
    const [patientResult, noteResult] = await Promise.all([
      searchPatientDirectory('', 300),
      supabase.from('nursing_notes').select('id,patient_id,note_type,note_text,assessment,intervention,evaluation,author_id,created_at').order('created_at', { ascending: false }).limit(100),
    ]);
    if (patientResult.error) toast({ title: 'Patient directory unavailable', description: patientResult.error.message, variant: 'destructive' });
    if (noteResult.error) toast({ title: 'Nursing notes unavailable', description: noteResult.error.message, variant: 'destructive' });
    setPatients((patientResult.data ?? []) as Patient[]);
    setNotes((noteResult.data ?? []) as NursingNote[]);
  };

  useEffect(() => { void load(); }, [user?.id]);

  const save = async () => {
    if (!patientId || !noteText.trim()) {
      toast({ title: 'Complete the nursing note', description: 'Select the patient and document the nursing note.', variant: 'destructive' });
      return;
    }
    setBusy(true);
    const { error } = await supabase.rpc('create_nursing_note', {
      _patient_id: patientId,
      _note_text: noteText,
      _note_type: noteType,
      _assessment: assessment || null,
      _intervention: intervention || null,
      _evaluation: evaluation || null,
    } as never);
    setBusy(false);
    if (error) return toast({ title: 'Nursing note failed', description: error.message, variant: 'destructive' });
    setNoteText(''); setAssessment(''); setIntervention(''); setEvaluation('');
    toast({ title: 'Nursing note saved', description: 'The note is now part of the patient clinical record.' });
    void load();
  };

  const patientName = (id: string) => {
    const p = patients.find((item) => item.id === id);
    return p ? `${p.first_name} ${p.last_name} · ${p.patient_code}` : id;
  };

  return <div className="space-y-6 animate-fade-in">
    <header className="flex flex-wrap items-center justify-between gap-3">
      <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><FileText className="h-6 w-6 text-primary" /> Nursing Notes</h1><p className="mt-1 text-sm text-muted-foreground">Routine nursing documentation is recorded here. Use Nursing Handover for shift-to-shift transfer of care.</p></div>
      <button type="button" onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4" /> Refresh</button>
    </header>
    <div className="grid gap-6 lg:grid-cols-[minmax(320px,420px)_minmax(0,1fr)]">
      <section className="card-medical rounded-3xl p-5 space-y-3">
        <div className="flex items-center gap-2"><Plus className="h-4 w-4 text-primary" /><h2 className="font-semibold">New nursing note</h2></div>
        <select className="input-medical w-full" value={patientId} onChange={(e) => setPatientId(e.target.value)}><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}</select>
        <select className="input-medical w-full" value={noteType} onChange={(e) => setNoteType(e.target.value)}><option value="progress">Progress note</option><option value="assessment">Nursing assessment</option><option value="intervention">Intervention</option><option value="evaluation">Evaluation</option><option value="admission">Admission nursing note</option></select>
        <textarea className="input-medical w-full" rows={5} value={noteText} onChange={(e) => setNoteText(e.target.value)} placeholder="Document observations, nursing care, patient response and relevant clinical events…" />
        <textarea className="input-medical w-full" rows={3} value={assessment} onChange={(e) => setAssessment(e.target.value)} placeholder="Assessment / observations (optional)" />
        <textarea className="input-medical w-full" rows={3} value={intervention} onChange={(e) => setIntervention(e.target.value)} placeholder="Intervention / nursing action (optional)" />
        <textarea className="input-medical w-full" rows={3} value={evaluation} onChange={(e) => setEvaluation(e.target.value)} placeholder="Evaluation / patient response (optional)" />
        <button type="button" disabled={busy} onClick={() => void save()} className="btn-primary w-full">{busy ? 'Saving…' : 'Save nursing note'}</button>
      </section>
      <section className="card-medical rounded-3xl p-5">
        <div className="mb-4"><h2 className="font-semibold">Recent nursing documentation</h2><p className="text-xs text-muted-foreground">Facility-scoped records available to authorized clinical staff.</p></div>
        <div className="space-y-3">{notes.map((note) => <article key={note.id} className="rounded-2xl border border-border p-4">
          <div className="flex flex-wrap items-center justify-between gap-2"><div><p className="font-medium">{patientName(note.patient_id)}</p><p className="text-[11px] uppercase tracking-wide text-primary">{note.note_type.replaceAll('_',' ')}</p></div><time className="text-xs text-muted-foreground">{new Date(note.created_at).toLocaleString()}</time></div>
          <p className="mt-3 whitespace-pre-wrap text-sm">{note.note_text}</p>
          {note.assessment && <p className="mt-2 text-xs"><strong>Assessment:</strong> {note.assessment}</p>}
          {note.intervention && <p className="mt-2 text-xs"><strong>Intervention:</strong> {note.intervention}</p>}
          {note.evaluation && <p className="mt-2 text-xs"><strong>Evaluation:</strong> {note.evaluation}</p>}
        </article>)}{notes.length === 0 && <p className="py-10 text-center text-sm text-muted-foreground">No nursing notes have been documented yet.</p>}</div>
      </section>
    </div>
  </div>;
}
