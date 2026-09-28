import { useEffect, useMemo, useState } from 'react';
import { ExternalLink, RefreshCw, Save } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import type { ClinicalReference } from '@/lib/clinicalReferences';

const blank: Partial<ClinicalReference> = {
  parameter: '', population_scope: 'adult', source_name: '', source_reference: '', source_url: '',
  source_is_ghana_specific: true, effective_date: '', normal_min: null, normal_max: null,
  thresholds: {}, display_text: '', last_reviewed_at: new Date().toISOString().slice(0, 10),
};

function reviewRequired(reference: ClinicalReference) {
  return new Date(reference.review_due_at).getTime() <= Date.now();
}

export default function ClinicalReferences() {
  const { user } = useAuth();
  const [references, setReferences] = useState<ClinicalReference[]>([]);
  const [selected, setSelected] = useState<ClinicalReference | null>(null);
  const [draft, setDraft] = useState<Partial<ClinicalReference>>(blank);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    const { data, error } = await (supabase as any)
      .from('clinical_reference_values')
      .select('id,parameter,population_scope,source_name,source_reference,source_url,source_is_ghana_specific,effective_date,normal_min,normal_max,thresholds,display_text,last_reviewed_at,review_due_at')
      .order('parameter');
    if (error) toast.error(error.message);
    else setReferences((data ?? []) as ClinicalReference[]);
    setLoading(false);
  };

  useEffect(() => { void load(); }, []);

  const canEdit = user?.role === 'admin';
  const sorted = useMemo(() => [...references].sort((a, b) => a.parameter.localeCompare(b.parameter)), [references]);

  const edit = (reference: ClinicalReference) => {
    setSelected(reference);
    setDraft(reference);
  };

  const startNew = () => {
    setSelected(null);
    setDraft({ ...blank, last_reviewed_at: new Date().toISOString().slice(0, 10) });
  };

  const save = async () => {
    if (!canEdit || !draft.parameter || !draft.source_name || !draft.source_reference || !draft.source_url || !draft.effective_date || !draft.display_text) {
      toast.error('Parameter, source name/reference/URL, effective date and display text are required.');
      return;
    }
    setSaving(true);
    const payload = {
      parameter: draft.parameter.trim(),
      population_scope: draft.population_scope || 'adult',
      source_name: draft.source_name.trim(),
      source_reference: draft.source_reference.trim(),
      source_url: draft.source_url.trim(),
      source_is_ghana_specific: Boolean(draft.source_is_ghana_specific),
      effective_date: draft.effective_date,
      normal_min: draft.normal_min === null || draft.normal_min === undefined || draft.normal_min === '' ? null : Number(draft.normal_min),
      normal_max: draft.normal_max === null || draft.normal_max === undefined || draft.normal_max === '' ? null : Number(draft.normal_max),
      thresholds: draft.thresholds ?? {},
      display_text: draft.display_text.trim(),
      last_reviewed_at: draft.last_reviewed_at || new Date().toISOString(),
      updated_by: user.id,
    };
    const query = selected
      ? (supabase as any).from('clinical_reference_values').update(payload).eq('id', selected.id)
      : (supabase as any).from('clinical_reference_values').insert(payload);
    const { error } = await query;
    setSaving(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success('Clinical reference saved.');
    await load();
    setSelected(null);
    setDraft(blank);
  };

  if (user?.role !== 'admin') {
    return <div className="card-medical p-6"><h1 className="text-xl font-semibold">Clinical Reference Values</h1><p className="mt-2 text-sm text-muted-foreground">Administrator access is required to manage clinical reference records.</p></div>;
  }

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-heading font-bold">Clinical Reference Values</h1>
        <p className="mt-1 text-sm text-muted-foreground">Source-controlled clinical helper text used by patient-facing vital-sign forms.</p>
      </header>
      <div className="grid gap-6 xl:grid-cols-[1.15fr_1fr]">
        <section className="card-medical overflow-hidden">
          <div className="flex items-center justify-between border-b p-4">
            <div><h2 className="font-semibold">Reference catalogue</h2><p className="text-xs text-muted-foreground">{references.length} active record{references.length === 1 ? '' : 's'}</p></div>
            <div className="flex gap-2"><button type="button" onClick={() => void load()} className="btn-secondary" title="Refresh"><RefreshCw className="h-4 w-4" /></button><button type="button" onClick={startNew} className="btn-primary">Add reference</button></div>
          </div>
          {loading ? <div className="p-5 text-sm text-muted-foreground">Loading references…</div> : (
            <div className="divide-y">
              {sorted.map((reference) => <button key={reference.id} type="button" onClick={() => edit(reference)} className="w-full p-4 text-left hover:bg-muted/40">
                <div className="flex flex-wrap items-center justify-between gap-2"><span className="font-medium">{reference.parameter}</span>{reviewRequired(reference) && <span className="text-xs font-semibold text-warning">Review required</span>}</div>
                <p className="mt-1 text-sm text-muted-foreground">{reference.display_text}</p>
                <p className="mt-1 text-xs text-muted-foreground">Source: {reference.source_name} · {reference.source_is_ghana_specific ? 'Ghana-specific' : 'International/supplemental'}</p>
              </button>)}
            </div>
          )}
        </section>
        <section className="card-medical p-5">
          <div className="mb-4"><h2 className="font-semibold">{selected ? 'Edit reference' : 'Add reference'}</h2><p className="text-xs text-muted-foreground">All clinical references must remain attributable and reviewable.</p></div>
          <div className="space-y-3">
            {[
              ['parameter','Parameter'],
              ['population_scope','Population scope'],
              ['source_name','Source name'],
              ['source_reference','Source reference'],
              ['source_url','Source URL'],
              ['effective_date','Effective date'],
              ['display_text','User-facing helper text'],
            ].map(([key,label]) => <label key={key} className="block space-y-1 text-sm"><span className="font-medium">{label}</span><input type={key==='effective_date'?'date':'text'} value={(draft as any)[key] ?? ''} onChange={e=>setDraft(current=>({...current,[key]:e.target.value}))} className="input-medical w-full" /></label>)}
            <div className="grid grid-cols-2 gap-3">
              <label className="space-y-1 text-sm"><span className="font-medium">Normal/reference min</span><input type="number" value={draft.normal_min ?? ''} onChange={e=>setDraft(current=>({...current,normal_min:e.target.value===''?null:Number(e.target.value)}))} className="input-medical w-full" /></label>
              <label className="space-y-1 text-sm"><span className="font-medium">Normal/reference max</span><input type="number" value={draft.normal_max ?? ''} onChange={e=>setDraft(current=>({...current,normal_max:e.target.value===''?null:Number(e.target.value)}))} className="input-medical w-full" /></label>
            </div>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={Boolean(draft.source_is_ghana_specific)} onChange={e=>setDraft(current=>({...current,source_is_ghana_specific:e.target.checked}))} /> Ghana-specific source</label>
            <label className="block space-y-1 text-sm"><span className="font-medium">Last reviewed</span><input type="date" value={draft.last_reviewed_at ? new Date(draft.last_reviewed_at).toISOString().slice(0,10) : ''} onChange={e=>setDraft(current=>({...current,last_reviewed_at:e.target.value}))} className="input-medical w-full" /></label>
            {selected && <div className="rounded-xl border border-muted p-3 text-xs text-muted-foreground"><p>Review due: {new Date(selected.review_due_at).toLocaleDateString()}</p><p className="mt-1">A review flag is shown here to administrators only.</p></div>}
            {draft.source_url && <a href={draft.source_url} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-xs underline"><ExternalLink className="h-3 w-3" />Open source</a>}
            <button type="button" onClick={() => void save()} disabled={saving} className="btn-primary inline-flex items-center gap-2"><Save className="h-4 w-4" />{saving ? 'Saving…' : 'Save reference'}</button>
          </div>
        </section>
      </div>
    </div>
  );
}
