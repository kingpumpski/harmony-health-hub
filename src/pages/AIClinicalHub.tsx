import { useEffect, useMemo, useState } from 'react';
import { BrainCircuit, Cpu, ShieldCheck, Sparkles, ClipboardList } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { useAuth } from '@/contexts/AuthContext';
import { buildAIClinicalContext } from '@/lib/aiClinicalContext';

const specialists = [
  { id: 'physician', title: 'AI Physician', description: 'Structured clinical reasoning support from symptoms, history, vitals and documented investigations.' },
  { id: 'surgeon', title: 'AI Surgeon', description: 'Surgical decision-support workspace for procedure planning, risk prompts and peri-operative considerations.' },
  { id: 'neurosurgeon', title: 'AI Neurosurgeon', description: 'Neurosurgical decision-support and visualization workspace for neurological cases and imaging review.' },
  { id: 'radiologist', title: 'AI Radiologist', description: 'Imaging review support and structured prompts for radiology findings.' },
  { id: 'ophthalmologist', title: 'AI Ophthalmologist', description: 'Ophthalmic examination and differential-support workspace.' },
  { id: 'pharmacist', title: 'AI Pharmacist', description: 'Medication and prescription review support, including interaction and safety prompts.' },
  { id: 'nurse', title: 'AI Specialist Nurse', description: 'Nursing workflow support for observations, care plans, escalation and monitoring.' },
] as const;

type SpecialistId = typeof specialists[number]['id'];
type Patient = { id: string; patient_code: string | null; first_name: string; last_name: string };
type Session = { id: string; specialist: string; status: string; review_status: string; created_at: string; model_provider: string | null; model_name: string | null };

export default function AIClinicalHub() {
  const { user } = useAuth();
  const [selected, setSelected] = useState<SpecialistId>('physician');
  const [patients, setPatients] = useState<Patient[]>([]);
  const [patientId, setPatientId] = useState('');
  const [sessions, setSessions] = useState<Session[]>([]);
  const [activeSessionId, setActiveSessionId] = useState('');
  const [loading, setLoading] = useState(false);
  const active = useMemo(() => specialists.find(item => item.id === selected), [selected]);

  const load = async () => {
    const [{ data: pts }, { data: rows }] = await Promise.all([
      supabase.from('patients').select('id, patient_code, first_name, last_name').order('created_at', { ascending: false }).limit(300),
      supabase.from('ai_clinical_sessions' as never).select('id, specialist, status, review_status, created_at, model_provider, model_name').order('created_at', { ascending: false }).limit(30),
    ]);
    setPatients((pts ?? []) as Patient[]);
    setSessions((rows ?? []) as unknown as Session[]);
  };

  useEffect(() => { void load(); }, []);

  const prepareCase = async () => {
    if (!user?.id || !patientId) {
      toast({ title: 'Select a patient', description: 'Choose the patient whose documented record will be used for this AI session.', variant: 'destructive' });
      return;
    }
    setLoading(true);
    try {
      const clinicalContext = await buildAIClinicalContext(patientId);
      const patient = patients.find(item => item.id === patientId);
      const inputSnapshot = {
        ...clinicalContext,
        patient: patient ?? clinicalContext.patient,
        captured_at: clinicalContext.generatedAt,
        source: 'harmony-health-hub',
      };
      const provenance = {
        created_from: 'AI Clinical Decision Support',
        specialist: selected,
        data_sources: ['patients', 'appointments', 'vital_signs', 'triage_assessments', 'encounters', 'lab_orders', 'lab_results', 'prescriptions', 'imaging_orders', 'procedure_notes', 'anesthetic_assessments', 'admissions'],
        generated_by: 'clinician_requested_session',
        context_generated_at: clinicalContext.generatedAt,
      };
      const { data, error } = await supabase.from('ai_clinical_sessions' as never).insert({
        patient_id: patientId,
        specialist: selected,
        status: 'draft',
        input_snapshot: inputSnapshot,
        provenance,
        created_by: user.id,
      } as never).select('id').single();
      if (error) throw new Error(error.message);
      const sessionId = (data as { id: string } | null)?.id ?? '';
      if (!sessionId) throw new Error('The AI session was created without an identifier');
      const { error: eventError } = await supabase.rpc('record_ai_clinical_event' as never, { _session_id: sessionId, _event_type: 'session_created', _metadata: { specialist: selected, context_sources: provenance.data_sources } } as never);
      if (eventError) throw new Error(eventError.message);
      setActiveSessionId(sessionId);
      toast({ title: 'AI case prepared', description: 'The current documented clinical context was captured. No AI finding has been generated.' });
      void load();
    } catch (error: any) {
      toast({ title: 'Could not prepare AI case', description: error.message ?? 'Clinical context could not be assembled.', variant: 'destructive' });
    } finally {
      setLoading(false);
    }
  };

  const requestAnalysis = async () => {
    if (!activeSessionId) {
      toast({ title: 'Prepare a case first', description: 'Select a patient and prepare the documented case before requesting analysis.', variant: 'destructive' });
      return;
    }
    setLoading(true);
    const { error } = await supabase.rpc('request_ai_clinical_analysis' as never, {
      _session_id: activeSessionId,
      _metadata: { requested_at: new Date().toISOString(), specialist: selected },
    } as never);
    if (!error) {
      toast({ title: 'Analysis request recorded', description: 'No model output is displayed until a configured AI provider returns a provenance-backed result.' });
      void load();
    } else {
      toast({ title: 'Analysis request failed', description: error.message, variant: 'destructive' });
    }
    setLoading(false);
  };

  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div><h1 className="text-2xl font-heading font-bold">AI Clinical Decision Support</h1><p className="text-muted-foreground">Persistent specialist workspaces with provenance and clinician-review controls.</p></div>
      <button onClick={prepareCase} disabled={loading} className="btn-primary inline-flex items-center gap-2"><Cpu className="w-4 h-4" /> {loading ? 'Working…' : 'Prepare case'}</button>
    </div>
    <div className="rounded-2xl border border-warning/20 bg-warning/5 p-4 text-sm flex gap-3"><ShieldCheck className="w-5 h-5 text-warning shrink-0" /><p>AI output is advisory only. It must be based on actual patient data and reviewed by an appropriately qualified clinician before any diagnosis, procedure, medication or treatment decision.</p></div>
    <div className="grid gap-6 lg:grid-cols-[320px_1fr]">
      <div className="card-medical p-5 space-y-3">
        <div className="flex items-center gap-3 mb-4"><BrainCircuit className="w-5 h-5 text-primary" /><div><h2 className="font-semibold">Specialists</h2><p className="text-xs text-muted-foreground">Select a decision-support domain.</p></div></div>
        {specialists.map(s => <button key={s.id} onClick={() => setSelected(s.id)} className={`w-full rounded-2xl border p-4 text-left transition ${selected === s.id ? 'border-primary bg-primary/10' : 'border-border hover:border-primary hover:bg-muted'}`}><p className="font-medium">{s.title}</p><p className="text-xs text-muted-foreground mt-1">{s.description}</p></button>)}
      </div>
      <div className="space-y-5">
        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-5"><div><h2 className="text-lg font-semibold">{active?.title}</h2><p className="text-sm text-muted-foreground">Clinical decision-support workspace</p></div><Sparkles className="w-5 h-5 text-primary" /></div>
          <div className="grid gap-4 md:grid-cols-2">
            <div className="rounded-2xl border border-border p-5"><p className="font-medium">Documented case</p><p className="text-sm text-muted-foreground mt-2">Select a patient. Preparation captures the current documented profile, clinical observations, encounters, investigations, medications and relevant workflow records.</p><select value={patientId} onChange={e => setPatientId(e.target.value)} className="input-medical mt-4 w-full"><option value="">Select patient…</option>{patients.map(p => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code ?? 'No code'}</option>)}</select></div>
            <div className="rounded-2xl border border-border p-5"><p className="font-medium">Output</p><p className="text-sm text-muted-foreground mt-2">No fabricated analysis is shown. The repository records the request and provenance; a configured AI provider must supply the actual model response before it can be stored as an AI finding.</p><button onClick={requestAnalysis} disabled={loading || !activeSessionId} className="btn-primary mt-4 text-xs">Request analysis</button></div>
          </div>
          <div className="mt-5 rounded-2xl border border-border p-5"><p className="font-medium">Specialist scope</p><p className="text-sm text-muted-foreground mt-2">{active?.description}</p><p className="text-xs text-muted-foreground mt-4">Any future AI response must include model/provider provenance and clinician-review state before becoming part of the medical record.</p></div>
        </div>
        <div className="card-medical p-5"><div className="flex items-center gap-2 mb-4"><ClipboardList className="w-5 h-5 text-primary" /><h2 className="font-semibold">Recent AI sessions</h2></div>{sessions.length === 0 ? <p className="text-sm text-muted-foreground">No AI sessions recorded yet.</p> : <div className="space-y-2">{sessions.map(session => <button key={session.id} onClick={() => { setActiveSessionId(session.id); setSelected((session.specialist as SpecialistId) || 'physician'); }} className="w-full rounded-xl border border-border p-3 text-left hover:border-primary"><div className="flex flex-wrap justify-between gap-2"><strong>{specialists.find(s => s.id === session.specialist)?.title ?? session.specialist}</strong><span className="text-xs text-muted-foreground">{new Date(session.created_at).toLocaleString()}</span></div><p className="text-xs text-muted-foreground mt-1">Status: {session.status.replaceAll('_', ' ')} · Review: {session.review_status.replaceAll('_', ' ')}</p></button>)}</div>}</div>
      </div>
    </div>
  </div>;
}
