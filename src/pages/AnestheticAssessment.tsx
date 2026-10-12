// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import { useEffect, useState } from 'react';
import { RefreshCw, ShieldCheck, Plus } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

interface Patient { id: string; first_name: string; last_name: string }
interface Assessment { id: string; patient_id: string; asa_class: string; cleared_for_procedure: boolean; status: string; created_at: string }
const ASA_OPTIONS = [
  { value: 'I', label: 'I — Healthy' }, { value: 'II', label: 'II — Mild systemic disease' },
  { value: 'III', label: 'III — Severe systemic disease' }, { value: 'IV', label: 'IV — Severe systemic disease, threat to life' },
  { value: 'V', label: 'V — Moribund' }, { value: 'VI', label: 'VI — Brain-dead organ donor' },
];

export default function AnestheticAssessment() {
  const { user } = useAuth(); const [patients, setPatients] = useState<Patient[]>([]); const [records, setRecords] = useState<Assessment[]>([]);
  const [pid, setPid] = useState(''); const [asa, setAsa] = useState('I'); const [airway, setAirway] = useState(''); const [cv, setCv] = useState(''); const [resp, setResp] = useState(''); const [allergies, setAllergies] = useState(''); const [meds, setMeds] = useState(''); const [fasting, setFasting] = useState(''); const [conclusion, setConclusion] = useState(''); const [cleared, setCleared] = useState(false); const [saving, setSaving] = useState(false); const [loading, setLoading] = useState(false);
  const load = async () => {
    if (loading) return;
    setLoading(true);
    try {
      const [{ data: p, error: patientError }, { data: r, error: recordError }] = await Promise.all([
        supabase.rpc('get_patient_directory', { _limit: 200 }),
        supabase.from('anesthetic_assessments').select('id, patient_id, asa_class, cleared_for_procedure, status, created_at').order('created_at', { ascending: false }).limit(50),
      ]);
      if (patientError || recordError) {
        toast({ title: 'Unable to load assessments', description: patientError?.message ?? recordError?.message ?? 'Please retry.', variant: 'destructive' });
        return;
      }
      setPatients((p ?? []) as Patient[]);
      setRecords((r ?? []) as Assessment[]);
    } catch (error) {
      toast({ title: 'Network error', description: error instanceof Error ? error.message : 'Could not load anesthetic assessments. Please retry.', variant: 'destructive' });
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => { void load(); }, []);
  const reset = () => { setPid(''); setAirway(''); setCv(''); setResp(''); setAllergies(''); setMeds(''); setFasting(''); setConclusion(''); setCleared(false); setAsa('I'); };
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (saving || !pid || !user?.id) return;
    setSaving(true);
    try {
      const { error } = await supabase.rpc('create_anesthetic_assessment', { _patient_id: pid, _asa_class: asa, _airway_assessment: airway || null, _cardiovascular: cv || null, _respiratory: resp || null, _allergies: allergies || null, _medications: meds || null, _fasting_status: fasting || null, _conclusions: conclusion || null, _cleared_for_procedure: cleared });
      if (error) {
        toast({ title: 'Failed to save assessment', description: error.message, variant: 'destructive' });
        return;
      }
      toast({ title: cleared ? 'Assessment saved — clearance recorded' : 'Assessment saved' });
      reset();
      await load();
    } catch (error) {
      toast({ title: 'Network error', description: error instanceof Error ? error.message : 'Could not save the assessment. Please retry.', variant: 'destructive' });
    } finally {
      setSaving(false);
    }
  };
  return <div className="space-y-6 animate-fade-in">
    <div className="flex items-start justify-between gap-3"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><ShieldCheck className="w-6 h-6 text-primary" /> Anesthetic Assessment</h1><p className="text-muted-foreground">Structured pre-procedure assessment with explicit clinician clearance.</p></div><button type="button" aria-label="Refresh anesthetic assessments" className="btn-secondary" disabled={loading || saving} onClick={() => void load()}><RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} /></button></div>
    <div className="rounded-xl border border-warning/20 bg-warning/5 p-3 text-sm text-muted-foreground">Clearance is a clinician attestation. The system does not autonomously determine anaesthetic fitness.</div>
    <form onSubmit={submit} className="card-medical p-6 space-y-4">
      <div className="grid md:grid-cols-2 gap-3"><select value={pid} onChange={e => setPid(e.target.value)} className="input-medical" required><option value="">Select patient…</option>{patients.map(p => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}</select><select value={asa} onChange={e => setAsa(e.target.value)} className="input-medical">{ASA_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}</select></div>
      <div className="grid md:grid-cols-2 gap-3"><textarea value={airway} onChange={e => setAirway(e.target.value)} rows={2} placeholder="Airway assessment (Mallampati, neck mobility, mouth opening)" className="input-medical" /><textarea value={cv} onChange={e => setCv(e.target.value)} rows={2} placeholder="Cardiovascular assessment" className="input-medical" /><textarea value={resp} onChange={e => setResp(e.target.value)} rows={2} placeholder="Respiratory assessment" className="input-medical" /><textarea value={allergies} onChange={e => setAllergies(e.target.value)} rows={2} placeholder="Allergies" className="input-medical" /><textarea value={meds} onChange={e => setMeds(e.target.value)} rows={2} placeholder="Current medications" className="input-medical" /><input value={fasting} onChange={e => setFasting(e.target.value)} placeholder="Fasting status" className="input-medical" /></div>
      <textarea value={conclusion} onChange={e => setConclusion(e.target.value)} rows={3} placeholder="Conclusions, risks and recommendations" className="input-medical w-full" />
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={cleared} onChange={e => setCleared(e.target.checked)} /> I confirm the patient is clinically cleared for the planned procedure</label>
      <button type="submit" disabled={saving} className="btn-primary"><Plus className="w-4 h-4 mr-2" /> {saving ? 'Saving…' : 'Submit assessment'}</button>
    </form>
    <div className="card-medical p-5"><h2 className="font-semibold mb-3">Recent assessments</h2>{loading && <p role="status" className="text-sm text-muted-foreground">Loading assessments…</p>}<div className="space-y-2">{records.map(r => <div key={r.id} className="rounded-xl border border-border p-3 text-sm flex justify-between gap-3"><span>ASA {r.asa_class} · {r.cleared_for_procedure ? <span className="text-success">Cleared</span> : <span className="text-warning">Pending</span>}</span><span className="text-muted-foreground">{new Date(r.created_at).toLocaleDateString()}</span></div>)}{!loading && records.length === 0 && <p className="text-sm text-muted-foreground">No assessments recorded.</p>}</div></div>
  </div>;
}
