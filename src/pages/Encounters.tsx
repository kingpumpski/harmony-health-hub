import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Stethoscope, Plus, FileText, Trash2, CheckCircle2, FlaskConical, Pill } from 'lucide-react';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string }
interface Encounter {
  id: string; patient_id: string; symptoms: string | null; clerking_notes: string | null;
  principal_diagnosis: string | null; treatment_plan: string | null; status: string; created_at: string;
}
interface Diagnosis { id: string; encounter_id: string; diagnosis: string; is_principal: boolean }
interface Prescription { id: string; medication: string; dosage: string | null; frequency: string | null; duration: string | null; status: string }

export default function Encounters() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [encounters, setEncounters] = useState<Encounter[]>([]);
  const [selected, setSelected] = useState<Encounter | null>(null);
  const [diagnoses, setDiagnoses] = useState<Diagnosis[]>([]);
  const [prescriptions, setPrescriptions] = useState<Prescription[]>([]);

  // new encounter form
  const [patientId, setPatientId] = useState('');
  const [symptoms, setSymptoms] = useState('');
  const [clerking, setClerking] = useState('');

  // diagnosis input
  const [newDx, setNewDx] = useState('');

  // prescription inputs
  const [med, setMed] = useState('');
  const [dose, setDose] = useState('');
  const [freq, setFreq] = useState('');
  const [duration, setDuration] = useState('');

  const loadAll = async () => {
    const [{ data: pts }, { data: encs }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name, patient_code').order('created_at', { ascending: false }).limit(200),
      supabase.from('encounters').select('*').order('created_at', { ascending: false }).limit(50),
    ]);
    setPatients(pts ?? []);
    setEncounters(encs ?? []);
  };

  const loadDetails = async (encounterId: string) => {
    const [{ data: dx }, { data: rx }] = await Promise.all([
      supabase.from('diagnoses').select('*').eq('encounter_id', encounterId),
      supabase.from('prescriptions').select('*').eq('encounter_id', encounterId).order('created_at', { ascending: false }),
    ]);
    setDiagnoses(dx ?? []);
    setPrescriptions((rx ?? []) as Prescription[]);
  };

  useEffect(() => { loadAll(); }, []);
  useEffect(() => { if (selected) loadDetails(selected.id); }, [selected]);

  const createEncounter = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!patientId) return toast({ title: 'Select a patient', variant: 'destructive' });
    const { data, error } = await supabase.from('encounters').insert({
      patient_id: patientId, symptoms, clerking_notes: clerking,
      practitioner_id: user?.id, status: 'draft',
    }).select().single();
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Encounter started' });
    setSymptoms(''); setClerking(''); setPatientId('');
    setSelected(data as Encounter);
    loadAll();
  };

  const addDiagnosis = async () => {
    if (!selected || !newDx.trim()) return;
    const { error } = await supabase.from('diagnoses').insert({
      encounter_id: selected.id, diagnosis: newDx.trim(),
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    setNewDx('');
    loadDetails(selected.id);
  };

  const setPrincipal = async (dx: Diagnosis) => {
    if (!selected) return;
    await supabase.from('diagnoses').update({ is_principal: false }).eq('encounter_id', selected.id);
    await supabase.from('diagnoses').update({ is_principal: true }).eq('id', dx.id);
    await supabase.from('encounters').update({ principal_diagnosis: dx.diagnosis }).eq('id', selected.id);
    setSelected({ ...selected, principal_diagnosis: dx.diagnosis });
    loadDetails(selected.id);
  };

  const removeDiagnosis = async (id: string) => {
    await supabase.from('diagnoses').delete().eq('id', id);
    if (selected) loadDetails(selected.id);
  };

  const addPrescription = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selected || !med.trim()) return;
    const { error } = await supabase.from('prescriptions').insert({
      encounter_id: selected.id, patient_id: selected.patient_id,
      prescribed_by: user?.id, medication: med.trim(),
      dosage: dose || null, frequency: freq || null, duration: duration || null,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    setMed(''); setDose(''); setFreq(''); setDuration('');
    loadDetails(selected.id);
  };

  const completeEncounter = async () => {
    if (!selected) return;
    if (!selected.principal_diagnosis) {
      return toast({ title: 'Principal diagnosis required', description: 'Mark one diagnosis as principal first.', variant: 'destructive' });
    }
    const { error } = await supabase.from('encounters').update({
      status: 'completed', completed_at: new Date().toISOString(),
    }).eq('id', selected.id);
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Encounter completed' });
    setSelected({ ...selected, status: 'completed' });
    loadAll();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
          <Stethoscope className="w-6 h-6 text-primary" />
          Clinical Encounters
        </h1>
        <p className="text-muted-foreground">Document consultations: symptoms → diagnoses → prescriptions → complete.</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[360px_1fr]">
        {/* LEFT: list + new encounter */}
        <div className="space-y-4">
          <form onSubmit={createEncounter} className="card-medical p-5 space-y-3">
            <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New Encounter</h2>
            <select value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full">
              <option value="">Select patient…</option>
              {patients.map((p) => (
                <option key={p.id} value={p.id}>{p.first_name} {p.last_name} ({p.patient_code})</option>
              ))}
            </select>
            <textarea value={symptoms} onChange={(e) => setSymptoms(e.target.value)} placeholder="Symptoms" className="input-medical w-full" rows={2} />
            <textarea value={clerking} onChange={(e) => setClerking(e.target.value)} placeholder="Clerking notes" className="input-medical w-full" rows={2} />
            <button className="btn-primary w-full">Start encounter</button>
          </form>

          <div className="card-medical p-5">
            <h2 className="font-semibold mb-3">Recent encounters</h2>
            <div className="space-y-2 max-h-[480px] overflow-auto">
              {encounters.map((e) => {
                const p = patients.find((x) => x.id === e.patient_id);
                return (
                  <button key={e.id} onClick={() => setSelected(e)}
                    className={`w-full text-left rounded-xl border p-3 transition ${selected?.id === e.id ? 'border-primary bg-primary/5' : 'border-border hover:bg-accent/40'}`}>
                    <div className="flex justify-between items-start">
                      <div>
                        <p className="font-medium text-sm">{p ? `${p.first_name} ${p.last_name}` : 'Patient'}</p>
                        <p className="text-xs text-muted-foreground">{new Date(e.created_at).toLocaleString()}</p>
                      </div>
                      <span className={`text-xs px-2 py-0.5 rounded-full ${e.status === 'completed' ? 'bg-success/15 text-success' : 'bg-warning/15 text-warning'}`}>
                        {e.status}
                      </span>
                    </div>
                    {e.principal_diagnosis && <p className="text-xs mt-1 truncate">Dx: {e.principal_diagnosis}</p>}
                  </button>
                );
              })}
              {encounters.length === 0 && <p className="text-sm text-muted-foreground">No encounters yet.</p>}
            </div>
          </div>
        </div>

        {/* RIGHT: detail */}
        <div className="card-medical p-6 min-h-[400px]">
          {!selected ? (
            <div className="h-full flex items-center justify-center text-muted-foreground">
              Select or create an encounter to begin.
            </div>
          ) : (
            <div className="space-y-6">
              <div className="flex justify-between items-start">
                <div>
                  <h2 className="text-lg font-semibold flex items-center gap-2"><FileText className="w-5 h-5" /> Encounter</h2>
                  <p className="text-sm text-muted-foreground">Started {new Date(selected.created_at).toLocaleString()}</p>
                </div>
                {selected.status !== 'completed' && (
                  <button onClick={completeEncounter} className="btn-primary inline-flex items-center gap-2">
                    <CheckCircle2 className="w-4 h-4" /> Complete
                  </button>
                )}
              </div>

              <section>
                <h3 className="font-semibold mb-2">Symptoms</h3>
                <p className="text-sm text-muted-foreground">{selected.symptoms || '—'}</p>
              </section>

              <section>
                <h3 className="font-semibold mb-2">Clerking notes</h3>
                <p className="text-sm text-muted-foreground whitespace-pre-wrap">{selected.clerking_notes || '—'}</p>
              </section>

              <section>
                <h3 className="font-semibold mb-2 flex items-center gap-2">
                  <FlaskConical className="w-4 h-4" /> Diagnoses
                </h3>
                <div className="flex gap-2 mb-3">
                  <input value={newDx} onChange={(e) => setNewDx(e.target.value)} className="input-medical flex-1" placeholder="Add diagnosis (e.g. Malaria)" />
                  <button onClick={addDiagnosis} className="btn-primary">Add</button>
                </div>
                <div className="space-y-2">
                  {diagnoses.map((d) => (
                    <div key={d.id} className="flex items-center justify-between rounded-xl border border-border p-3">
                      <div className="flex items-center gap-2">
                        <span>{d.diagnosis}</span>
                        {d.is_principal && <span className="text-xs px-2 py-0.5 rounded-full bg-primary/15 text-primary">Principal</span>}
                      </div>
                      <div className="flex gap-2">
                        {!d.is_principal && (
                          <button onClick={() => setPrincipal(d)} className="text-xs text-primary hover:underline">Set principal</button>
                        )}
                        <button onClick={() => removeDiagnosis(d.id)} className="text-critical">
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  ))}
                  {diagnoses.length === 0 && <p className="text-sm text-muted-foreground">No diagnoses yet.</p>}
                </div>
              </section>

              <section>
                <h3 className="font-semibold mb-2 flex items-center gap-2">
                  <Pill className="w-4 h-4" /> Prescriptions
                </h3>
                <form onSubmit={addPrescription} className="grid grid-cols-2 md:grid-cols-4 gap-2 mb-3">
                  <input value={med} onChange={(e) => setMed(e.target.value)} className="input-medical" placeholder="Medication" />
                  <input value={dose} onChange={(e) => setDose(e.target.value)} className="input-medical" placeholder="Dose" />
                  <input value={freq} onChange={(e) => setFreq(e.target.value)} className="input-medical" placeholder="Frequency" />
                  <input value={duration} onChange={(e) => setDuration(e.target.value)} className="input-medical" placeholder="Duration" />
                  <button className="btn-primary col-span-2 md:col-span-4">Prescribe</button>
                </form>
                <div className="space-y-2">
                  {prescriptions.map((p) => (
                    <div key={p.id} className="rounded-xl border border-border p-3 text-sm flex justify-between items-center">
                      <div>
                        <span className="font-medium">{p.medication}</span>
                        <span className="text-muted-foreground"> · {p.dosage} · {p.frequency} · {p.duration}</span>
                      </div>
                      <span className={`text-xs px-2 py-0.5 rounded-full ${p.status === 'dispensed' ? 'bg-success/15 text-success' : 'bg-warning/15 text-warning'}`}>{p.status}</span>
                    </div>
                  ))}
                  {prescriptions.length === 0 && <p className="text-sm text-muted-foreground">No prescriptions yet.</p>}
                </div>
              </section>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
