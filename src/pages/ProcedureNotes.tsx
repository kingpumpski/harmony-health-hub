import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { ClipboardList, Plus } from 'lucide-react';

const PROCEDURE_TEMPLATES: Record<string, { indication: string; technique: string; postOp: string }> = {
  'Appendectomy': {
    indication: 'Acute appendicitis confirmed clinically and radiologically.',
    technique: 'Patient under GA, supine. Standard 3-port laparoscopic approach. Mesoappendix divided with diathermy. Appendix base secured with endoloops, transected. Specimen retrieved in endobag.',
    postOp: 'IV antibiotics 24h, oral diet at 6h, mobilize day 1, discharge day 1-2. Follow up in 7 days.',
  },
  'Caesarean Section': {
    indication: 'Documented obstetric indication (e.g. CPD, fetal distress, previous CS).',
    technique: 'Spinal anaesthesia. Pfannenstiel incision. Layered entry to peritoneum. Lower segment transverse uterine incision. Live infant delivered. Placenta delivered, uterus closed in 2 layers.',
    postOp: 'Oxytocin infusion, IV antibiotics 24h, analgesia, early ambulation. Discharge day 3.',
  },
  'Cataract Surgery': {
    indication: 'Visually significant cataract, BCVA worse than 6/18.',
    technique: 'Topical anaesthesia. Clear corneal phacoemulsification. Capsulorrhexis 5.5mm. Hydrodissection, phaco of nucleus, IOL implant in capsular bag.',
    postOp: 'Topical antibiotic+steroid drops QID x 4 weeks. Review day 1, week 1, week 4.',
  },
  'Tooth Extraction': {
    indication: 'Non-restorable tooth / severe periodontitis.',
    technique: 'Local infiltration of lignocaine 2% with adrenaline. Elevation and extraction with forceps. Socket inspected for retained roots. Pressure haemostasis.',
    postOp: 'Bite on gauze 30 min, NSAIDs PRN, soft diet 24h, no rinsing for 24h. Review in 1 week.',
  },
  'D&C': {
    indication: 'Incomplete miscarriage / retained products of conception.',
    technique: 'Spinal/GA. Lithotomy position. Cervix dilated to Hegar 10. Suction evacuation followed by gentle sharp curettage.',
    postOp: 'Oxytocics, antibiotics, analgesia. Discharge same day if stable. Review in 2 weeks.',
  },
  'Custom': { indication: '', technique: '', postOp: '' },
};

interface Patient { id: string; first_name: string; last_name: string }
interface Note { id: string; patient_id: string; procedure_name: string; status: string; created_at: string }

export default function ProcedureNotes() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [notes, setNotes] = useState<Note[]>([]);
  const [pid, setPid] = useState('');
  const [proc, setProc] = useState('Custom');
  const [indication, setIndication] = useState('');
  const [technique, setTechnique] = useState('');
  const [findings, setFindings] = useState('');
  const [complications, setComplications] = useState('');
  const [postOp, setPostOp] = useState('');

  useEffect(() => {
    supabase.from('patients').select('id, first_name, last_name').limit(200).then(({ data }) => setPatients(data ?? []));
    load();
  }, []);

  const load = () => supabase.from('procedure_notes').select('*').order('created_at', { ascending: false }).limit(50).then(({ data }) => setNotes(data ?? []));

  const applyTemplate = (name: string) => {
    setProc(name);
    const t = PROCEDURE_TEMPLATES[name];
    if (t) { setIndication(t.indication); setTechnique(t.technique); setPostOp(t.postOp); }
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid || !proc) return;
    const { error } = await supabase.from('procedure_notes').insert({
      patient_id: pid, procedure_name: proc, template_used: proc,
      indication, technique, findings, complications, post_op_plan: postOp,
      performed_by: user?.id, status: 'completed',
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Procedure note saved' });
    setIndication(''); setTechnique(''); setFindings(''); setComplications(''); setPostOp(''); setProc('Custom');
    load();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><ClipboardList className="w-6 h-6 text-primary" /> Procedure Notes</h1>
        <p className="text-muted-foreground">Templated procedure documentation following accepted standards.</p>
      </div>

      <form onSubmit={submit} className="card-medical p-6 space-y-3">
        <div className="grid gap-3 md:grid-cols-2">
          <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical">
            <option value="">Select patient…</option>
            {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
          </select>
          <select value={proc} onChange={(e) => applyTemplate(e.target.value)} className="input-medical">
            {Object.keys(PROCEDURE_TEMPLATES).map((k) => <option key={k}>{k}</option>)}
          </select>
        </div>
        <textarea value={indication} onChange={(e) => setIndication(e.target.value)} rows={2} placeholder="Indication" className="input-medical w-full" />
        <textarea value={technique} onChange={(e) => setTechnique(e.target.value)} rows={4} placeholder="Technique" className="input-medical w-full" />
        <textarea value={findings} onChange={(e) => setFindings(e.target.value)} rows={2} placeholder="Findings" className="input-medical w-full" />
        <textarea value={complications} onChange={(e) => setComplications(e.target.value)} rows={2} placeholder="Complications (if any)" className="input-medical w-full" />
        <textarea value={postOp} onChange={(e) => setPostOp(e.target.value)} rows={2} placeholder="Post-op plan" className="input-medical w-full" />
        <button className="btn-primary"><Plus className="w-4 h-4 mr-2" /> Save procedure note</button>
      </form>

      <div className="card-medical p-5">
        <h2 className="font-semibold mb-3">Recent procedure notes</h2>
        <div className="space-y-2">
          {notes.map((n) => {
            const p = patients.find(x => x.id === n.patient_id);
            return (
              <div key={n.id} className="rounded-xl border border-border p-3 flex justify-between text-sm">
                <span><strong>{n.procedure_name}</strong> — {p ? `${p.first_name} ${p.last_name}` : 'Patient'}</span>
                <span className="text-muted-foreground">{new Date(n.created_at).toLocaleDateString()}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
