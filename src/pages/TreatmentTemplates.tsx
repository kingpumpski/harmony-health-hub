// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import MedicalTermInput from '@/components/MedicalTermInput';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Layers, Plus, Sparkles, Search } from 'lucide-react';
import { RecordList, type RecordColumn } from '@/components/records/RecordList';

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
  const [listQuery, setListQuery] = useState('');
  const [aiOnly, setAiOnly] = useState('all');

  const load = () => supabase.from('treatment_templates').select('id,name,diagnosis,description,prescriptions,is_ai_generated,created_at').order('created_at', { ascending: false }).then(({ data }) => setTemplates((data ?? []) as Template[]));
  useEffect(() => { load(); }, []);

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name) return;
    const prescriptions = rxText.split('\\n').filter(Boolean).map(line => {
      const [med, dose, freq, dur] = line.split('|').map(s => s.trim());
      return { medication: med, dosage: dose, frequency: freq, duration: dur };
    });
    const { error } = await supabase.rpc('create_treatment_template_workflow', {
      _name: name,
      _diagnosis: diagnosis || null,
      _description: description || null,
      _prescriptions: prescriptions,
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Template saved' });
    setName(''); setDiagnosis(''); setDescription(''); setRxText('');
    load();
  };

  const visibleTemplates = templates.filter((t) => { const q = listQuery.trim().toLowerCase(); const matchesQuery = !q || `${t.name} ${t.diagnosis} ${t.description}`.toLowerCase().includes(q); const matchesAi = aiOnly === 'all' || (aiOnly === 'ai' ? t.is_ai_generated : !t.is_ai_generated); return matchesQuery && matchesAi; });

  const columns: RecordColumn<Template>[] = [
    { key: 'name', header: 'Template', sortable: true, render: (t) => <div><p className="font-medium">{t.name} {t.is_ai_generated && <span className="ml-1 text-xs px-1.5 py-0.5 rounded bg-accent/15 text-accent">AI</span>}</p><p className="text-xs text-muted-foreground">{t.description || 'No description recorded.'}</p></div> },
    { key: 'diagnosis', header: 'Diagnosis', sortable: true, hideBelow: 'md', render: (t) => t.diagnosis || '—' },
    { key: 'prescriptions', header: 'Protocol', hideBelow: 'lg', render: (t) => Array.isArray(t.prescriptions) && t.prescriptions.length > 0 ? <details onClick={(e) => e.stopPropagation()}><summary className="cursor-pointer text-sm text-primary">{t.prescriptions.length} medication{t.prescriptions.length === 1 ? '' : 's'}</summary><ul className="mt-2 space-y-1 text-xs">{t.prescriptions.map((p: any, i: number) => <li key={i}>• {p.medication} — {p.dosage} {p.frequency} × {p.duration}</li>)}</ul></details> : <span className="text-muted-foreground">No medications</span> },
    { key: 'created_at', header: 'Created', sortable: true, hideBelow: 'lg', render: (t) => <time dateTime={t.created_at} title={new Date(t.created_at).toLocaleString()}>{new Date(t.created_at).toLocaleDateString()}</time> },
  ];

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
            <textarea value={rxText} onChange={(e) => setRxText(e.target.value)} placeholder={`One per line:
Medication | Dose | Frequency | Duration
Amoxicillin | 500mg | TDS | 7 days`} rows={4} className="input-medical w-full font-mono text-xs" />
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
          <RecordList
            title="Template library"
            description={templates.length + " saved care plan" + (templates.length === 1 ? "" : "s")}
            data={visibleTemplates}
            columns={columns}
            rowKey={(t) => t.id}
            onRefresh={load}
            searchSlot={<div className="flex flex-col gap-2 sm:flex-row"><div className="flex min-w-0 flex-1 items-center gap-2"><Search className="h-4 w-4 text-muted-foreground" /><input value={listQuery} onChange={(e) => setListQuery(e.target.value)} className="input-medical w-full" placeholder="Search template, diagnosis or description…" aria-label="Search treatment templates" /></div><select value={aiOnly} onChange={(e) => setAiOnly(e.target.value)} className="input-medical sm:w-44" aria-label="Filter AI generated templates"><option value="all">All templates</option><option value="ai">AI generated</option><option value="manual">Manual</option></select></div>}
            emptyState={{ title: 'No treatment templates', description: 'Create a standardized care plan using the form.' }}
          />
        </div>
      </div>
    </div>
  );
}
