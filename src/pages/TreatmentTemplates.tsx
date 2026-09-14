import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import MedicalTermInput from '@/components/MedicalTermInput';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Layers, Plus, Sparkles } from 'lucide-react';

interface Template { id: string; name: string; diagnosis: string; description: string; prescriptions: any; is_ai_generated: boolean; created_at: string }

export default function TreatmentTemplates() {
  const { user } = useAuth();
  const [templates, setTemplates] = useState<Template[]>([]);
  const [name, setName] = useState('');
  const [diagnosis, setDiagnosis] = useState('');
  const [description, setDescription] = useState('');
  const [rxText, setRxText] = useState('');
  const [synthBusy, setSynthBusy] = useState(false);
  const [synthDx, setSynthDx] = useState('');

  const load = () => supabase.from('treatment_templates').select('*').order('created_at', { ascending: false }).then(({ data }) => setTemplates((data ?? []) as Template[]));
  useEffect(() => { load(); }, []);

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name) return;
    const prescriptions = rxText.split('\n').filter(Boolean).map(line => {
      const [med, dose, freq, dur] = line.split('|').map(s => s.trim());
      return { medication: med, dosage: dose, frequency: freq, duration: dur };
    });
    const { error } = await supabase.from('treatment_templates').insert({
      name, diagnosis, description, prescriptions, created_by: user?.id,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Template saved' });
    setName(''); setDiagnosis(''); setDescription(''); setRxText('');
    load();
  };

  const synthesize = async () => {
    if (!synthDx) return;
    setSynthBusy(true);
    const { data, error } = await supabase.functions.invoke('ai-clinical-assist', {
      body: { mode: 'synthesize_protocol', diagnosis: synthDx },
    });
    setSynthBusy(false);
    if (error || data?.error) return toast({ title: 'Synthesis failed', description: data?.error ?? error?.message, variant: 'destructive' });
    toast({ title: 'Protocol synthesized', description: 'Awaiting review in AI Hub.' });
    setSynthDx('');
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Layers className="w-6 h-6 text-primary" /> Treatment Templates</h1>
        <p className="text-muted-foreground">Standardized care plans practitioners can apply and customize.</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[420px_1fr]">
        <div className="space-y-4">
          <form onSubmit={save} className="card-medical p-5 space-y-3">
            <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New template</h2>
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Template name (e.g. Adult Malaria Protocol)" className="input-medical w-full" />
            <MedicalTermInput value={diagnosis} onChange={setDiagnosis} placeholder="Diagnosis covered" className="w-full" diagnosisOnly />
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Description / when to apply" rows={2} className="input-medical w-full" />
            <textarea value={rxText} onChange={(e) => setRxText(e.target.value)} placeholder={`One per line:\nMedication | Dose | Frequency | Duration\nAmoxicillin | 500mg | TDS | 7 days`} rows={4} className="input-medical w-full font-mono text-xs" />
            <button className="btn-primary w-full">Save template</button>
          </form>

          <div className="card-medical p-5 space-y-3">
            <h2 className="font-semibold flex items-center gap-2"><Sparkles className="w-4 h-4 text-primary" /> AI protocol synthesis</h2>
            <p className="text-xs text-muted-foreground">Generate a house protocol from past cases. Needs ≥3 cases for that diagnosis.</p>
            <MedicalTermInput value={synthDx} onChange={setSynthDx} placeholder="Diagnosis (e.g. Hypertension)" className="w-full" diagnosisOnly />
            <button onClick={synthesize} disabled={synthBusy} className="btn-accent w-full">{synthBusy ? 'Synthesizing…' : 'Synthesize'}</button>
          </div>
        </div>

        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Library</h2>
          <div className="space-y-3">
            {templates.map((t) => (
              <div key={t.id} className="rounded-xl border border-border p-4">
                <div className="flex justify-between items-start">
                  <div>
                    <p className="font-medium flex items-center gap-2">
                      {t.name}
                      {t.is_ai_generated && <span className="text-xs px-1.5 py-0.5 rounded bg-accent/15 text-accent">AI</span>}
                    </p>
                    <p className="text-xs text-muted-foreground">{t.diagnosis}</p>
                  </div>
                </div>
                {t.description && <p className="text-sm mt-2">{t.description}</p>}
                {Array.isArray(t.prescriptions) && t.prescriptions.length > 0 && (
                  <ul className="mt-2 text-xs space-y-1">
                    {t.prescriptions.map((p: any, i: number) => (
                      <li key={i}>• {p.medication} — {p.dosage} {p.frequency} × {p.duration}</li>
                    ))}
                  </ul>
                )}
              </div>
            ))}
            {templates.length === 0 && <p className="text-sm text-muted-foreground">No templates yet.</p>}
          </div>
        </div>
      </div>
    </div>
  );
}
