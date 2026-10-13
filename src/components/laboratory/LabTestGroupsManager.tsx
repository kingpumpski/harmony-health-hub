// @ts-nocheck -- generated Supabase types have not yet been regenerated for the panel RPCs.
import { useEffect, useMemo, useState } from 'react';
import { ArrowDown, ArrowLeft, ArrowUp, Plus, Save } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

interface TestCatalogueItem {
  id: string;
  test_code: string;
  test_name: string;
  category: string | null;
  parameters?: Array<{ code: string; label?: string; name?: string; unit?: string; reference_low?: number | null; reference_high?: number | null }>;
}

interface PanelTest extends TestCatalogueItem { display_order: number; active: boolean }
interface LabPanel {
  id: string;
  group_name: string;
  group_code: string;
  description: string | null;
  default_charge: number;
  is_active: boolean;
  tests: PanelTest[];
}

interface Props { catalogue: TestCatalogueItem[] }

export default function LabTestGroupsManager({ catalogue }: Props) {
  const [panels, setPanels] = useState<LabPanel[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [code, setCode] = useState('');
  const [description, setDescription] = useState('');
  const [charge, setCharge] = useState('0');
  const [selectedTests, setSelectedTests] = useState<string[]>([]);
  const [search, setSearch] = useState('');

  const load = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('get_laboratory_test_groups', { _include_inactive: true } as never);
    if (error) {
      toast({ title: 'Laboratory panels unavailable', description: error.message, variant: 'destructive' });
    } else {
      setPanels((data ?? []) as unknown as LabPanel[]);
    }
    setLoading(false);
  };

  useEffect(() => { void load(); }, []);

  const filteredCatalogue = useMemo(() => catalogue.filter((test) =>
    `${test.test_code} ${test.test_name} ${test.category ?? ''}`.toLowerCase().includes(search.toLowerCase())
  ), [catalogue, search]);

  const reset = () => {
    setEditingId(null);
    setName('');
    setCode('');
    setDescription('');
    setCharge('0');
    setSelectedTests([]);
  };

  const editPanel = (panel: LabPanel) => {
    setEditingId(panel.id);
    setName(panel.group_name);
    setCode(panel.group_code);
    setDescription(panel.description ?? '');
    setCharge(String(panel.default_charge));
    setSelectedTests(panel.tests.map((test) => test.id));
  };

  const moveTest = (index: number, direction: -1 | 1) => {
    const target = index + direction;
    if (target < 0 || target >= selectedTests.length) return;
    setSelectedTests((current) => {
      const next = [...current];
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  };

  const savePanel = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!name.trim() || !code.trim() || !selectedTests.length || !Number.isFinite(Number(charge)) || Number(charge) < 0) {
      toast({ title: 'Panel details required', description: 'Enter a name, code, non-negative tariff and at least one active test.', variant: 'destructive' });
      return;
    }
    setSaving(true);
    const { error } = await supabase.rpc('save_laboratory_test_group', {
      _group_id: editingId,
      _group_name: name.trim(),
      _group_code: code.trim(),
      _description: description.trim() || null,
      _default_charge: Number(charge),
      _test_ids: selectedTests,
      _is_active: true,
    } as never);
    setSaving(false);
    if (error) {
      toast({ title: 'Could not save laboratory panel', description: error.message, variant: 'destructive' });
      return;
    }
    toast({ title: editingId ? 'Laboratory panel updated' : 'Laboratory panel created' });
    reset();
    await load();
  };

  const deactivate = async (panel: LabPanel) => {
    const { error } = await supabase.rpc('save_laboratory_test_group', {
      _group_id: panel.id,
      _group_name: panel.group_name,
      _group_code: panel.group_code,
      _description: panel.description,
      _default_charge: panel.default_charge,
      _test_ids: panel.tests.map((test) => test.id),
      _is_active: false,
    } as never);
    if (error) {
      toast({ title: 'Could not deactivate panel', description: error.message, variant: 'destructive' });
      return;
    }
    toast({ title: 'Laboratory panel deactivated' });
    await load();
  };

  return (
    <main className="mx-auto max-w-6xl space-y-5 p-4 sm:p-6" aria-labelledby="lab-panels-title">
      <header className="flex flex-wrap items-start justify-between gap-4 rounded-2xl border border-border bg-card p-5 shadow-sm">
        <div>
          <Link to="/laboratory" className="inline-flex items-center gap-2 text-xs font-medium text-primary"><ArrowLeft className="h-4 w-4" /> Laboratory worklist</Link>
          <h1 id="lab-panels-title" className="mt-3 text-2xl font-semibold">Laboratory panels</h1>
          <p className="mt-1 max-w-2xl text-sm text-muted-foreground">Bundle active catalogue tests under one facility tariff. Each test keeps its own parameters and approval workflow.</p>
        </div>
      </header>

      <div className="grid gap-5 xl:grid-cols-[1fr_1.15fr]">
        <form onSubmit={savePanel} className="space-y-4 rounded-2xl border border-border bg-card p-5 shadow-sm">
          <div className="flex items-center justify-between gap-3"><h2 className="font-semibold">{editingId ? 'Edit panel' : 'Create panel'}</h2>{editingId && <button type="button" onClick={reset} className="btn-ghost text-xs">Cancel edit</button>}</div>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="text-xs font-medium">Panel name<input value={name} onChange={(event) => setName(event.target.value)} className="input-medical mt-1 w-full" placeholder="Medical Examination" /></label>
            <label className="text-xs font-medium">Panel code<input value={code} onChange={(event) => setCode(event.target.value)} className="input-medical mt-1 w-full" placeholder="MED-EXAM-001" /></label>
            <label className="text-xs font-medium sm:col-span-2">Description<input value={description} onChange={(event) => setDescription(event.target.value)} className="input-medical mt-1 w-full" placeholder="Optional clinical description" /></label>
            <label className="text-xs font-medium sm:col-span-2">Single panel tariff (GHS)<input type="number" min="0" step="0.01" value={charge} onChange={(event) => setCharge(event.target.value)} className="input-medical mt-1 w-full" /></label>
          </div>

          <section className="space-y-2">
            <div className="flex items-center justify-between"><h3 className="text-sm font-semibold">Tests in order</h3><span className="text-xs text-muted-foreground">{selectedTests.length} selected</span></div>
            {selectedTests.map((testId, index) => {
              const test = catalogue.find((item) => item.id === testId)
                ?? panels.flatMap((panel) => panel.tests).find((item) => item.id === testId);
              return <div key={testId} className="flex items-center gap-2 rounded-lg border border-border p-2">
                <span className="min-w-0 flex-1 text-sm">{test?.test_name ?? testId}{test && !test.active && <span className="ml-2 text-xs text-critical">Inactive — remove before saving</span>}</span>
                <button type="button" disabled={index === 0} onClick={() => moveTest(index, -1)} className="btn-ghost p-1" aria-label="Move test up"><ArrowUp className="h-4 w-4" /></button>
                <button type="button" disabled={index === selectedTests.length - 1} onClick={() => moveTest(index, 1)} className="btn-ghost p-1" aria-label="Move test down"><ArrowDown className="h-4 w-4" /></button>
                <button type="button" onClick={() => setSelectedTests((current) => current.filter((id) => id !== testId))} className="btn-ghost text-xs text-critical">Remove</button>
              </div>;
            })}
          </section>

          <div className="space-y-2">
            <input value={search} onChange={(event) => setSearch(event.target.value)} className="input-medical w-full" placeholder="Search active catalogue tests" aria-label="Search tests" />
            <div className="max-h-56 space-y-1 overflow-y-auto rounded-xl border border-border p-2">
              {filteredCatalogue.map((test) => <label key={test.id} className="flex cursor-pointer items-start gap-2 rounded-lg p-2 hover:bg-muted/50">
                <input type="checkbox" checked={selectedTests.includes(test.id)} onChange={(event) => setSelectedTests((current) => event.target.checked ? [...current, test.id] : current.filter((id) => id !== test.id))} />
                <span className="min-w-0 text-sm"><span className="font-medium">{test.test_name}</span><span className="ml-2 text-xs text-muted-foreground">{test.test_code} · {test.parameters?.length ?? 0} parameters</span></span>
              </label>)}
              {!filteredCatalogue.length && <p className="p-2 text-xs text-muted-foreground">No active tests match.</p>}
            </div>
          </div>
          <button type="submit" disabled={saving} className="btn-primary inline-flex items-center gap-2 disabled:opacity-60"><Save className="h-4 w-4" />{saving ? 'Saving…' : editingId ? 'Save panel' : 'Create panel'}</button>
        </form>

        <section className="space-y-3">
          <div className="flex items-center justify-between"><h2 className="font-semibold">Facility panels</h2><span className="text-xs text-muted-foreground">{panels.length} total</span></div>
          {loading ? <p className="rounded-xl border border-border p-5 text-sm text-muted-foreground">Loading panels…</p> : panels.map((panel) => <article key={panel.id} className="rounded-2xl border border-border bg-card p-4 shadow-sm">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div><div className="flex items-center gap-2"><h3 className="font-semibold">{panel.group_name}</h3><span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${panel.is_active ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'}`}>{panel.is_active ? 'Active' : 'Inactive'}</span></div><p className="mt-1 text-xs text-muted-foreground">{panel.group_code} · {panel.tests.length} tests · GHS {Number(panel.default_charge).toFixed(2)}</p>{panel.description && <p className="mt-2 text-sm">{panel.description}</p>}</div>
              <div className="flex gap-2"><button type="button" onClick={() => editPanel(panel)} className="btn-secondary text-xs">Edit</button>{panel.is_active && <button type="button" onClick={() => void deactivate(panel)} className="btn-ghost text-xs text-critical">Deactivate</button>}</div>
            </div>
            <ol className="mt-3 grid gap-2 sm:grid-cols-2">{panel.tests.map((test, index) => <li key={test.id} className="rounded-lg bg-muted/30 p-2 text-xs"><span className="font-medium">{index + 1}. {test.test_name}</span>{!test.active && <span className="ml-2 text-critical">Inactive</span>}<span className="mt-1 block text-muted-foreground">{test.parameters?.length ?? 0} structured parameters · {test.specimen_type ?? 'Specimen not set'}</span></li>)}</ol>
          </article>)}
          {!loading && panels.length === 0 && <div className="rounded-xl border border-dashed border-border p-6 text-sm text-muted-foreground"><Plus className="mb-2 h-5 w-5" />No panels configured for this facility.</div>}
        </section>
      </div>
    </main>
  );
}
