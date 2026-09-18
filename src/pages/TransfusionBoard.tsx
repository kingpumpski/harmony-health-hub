import { FormEvent, useCallback, useEffect, useState } from 'react';
import { AlertTriangle, Droplets, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { searchPatientDirectory } from '@/lib/patientDirectory';

type Row = { id: string; patient_id: string; blood_product: string; unit_identifier: string; blood_group: string | null; status: string; reaction_observed: boolean; reaction_notes: string | null };
type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
const statuses = ['planned', 'issued', 'running', 'completed', 'stopped', 'cancelled'];

export default function TransfusionBoard() {
  const [rows, setRows] = useState<Row[]>([]); const [patients, setPatients] = useState<Patient[]>([]); const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({ patientId: '', bloodProduct: '', unitIdentifier: '', bloodGroup: '', consentConfirmed: false });
  const load = useCallback(async () => {
    const [workspace, p] = await Promise.all([
      supabase.rpc('get_operational_workspace', { _module: 'transfusion', _limit: 150 }),
      searchPatientDirectory('', 500),
    ]);
    const r = { data: (workspace.data as any)?.records ?? [], error: workspace.error };
    if (p.error || r.error) toast({ title: 'Unable to load transfusions', description: (p.error || r.error)?.message, variant: 'destructive' });
    setPatients((p.data ?? []) as Patient[]); setRows((r.data ?? []) as Row[]);
  }, []);
  useEffect(() => { void load(); }, [load]);
  const create = async (event: FormEvent) => {
    event.preventDefault();
    if (!form.patientId || !form.bloodProduct.trim() || !form.unitIdentifier.trim()) { toast({ title: 'Patient, blood product and unit identifier are required', variant: 'destructive' }); return; }
    if (!form.consentConfirmed) { toast({ title: 'Confirm documented transfusion consent before scheduling', variant: 'destructive' }); return; }
    setBusy(true); const { error } = await (supabase as any).rpc('create_transfusion_record', { _patient_id: form.patientId, _blood_product: form.bloodProduct.trim(), _unit_identifier: form.unitIdentifier.trim(), _blood_group: form.bloodGroup.trim() || null, _consent_confirmed: true }); setBusy(false);
    if (error) { toast({ title: 'Transfusion record failed', description: error.message, variant: 'destructive' }); return; }
    setForm({ patientId: '', bloodProduct: '', unitIdentifier: '', bloodGroup: '', consentConfirmed: false }); toast({ title: 'Transfusion record created' }); void load();
  };
  const transition = async (id: string, status: string) => {
    setBusy(true); const { error } = await (supabase as any).rpc('record_transfusion_event', { _record_id: id, _status: status, _reaction_observed: false, _reaction_notes: null }); setBusy(false);
    if (error) toast({ title: 'Transition failed', description: error.message, variant: 'destructive' }); else { toast({ title: 'Transfusion status updated' }); void load(); }
  };
  const reaction = async (id: string) => {
    const notes = window.prompt('Document the observed reaction.'); if (notes === null) return; setBusy(true);
    const { error } = await (supabase as any).rpc('record_transfusion_reaction', { _record_id: id, _reaction_observed: true, _reaction_notes: notes.trim() || null }); setBusy(false);
    if (error) toast({ title: 'Reaction update failed', description: error.message, variant: 'destructive' }); else { toast({ title: 'Reaction documented' }); void load(); }
  };
  const patient = (id: string) => { const p = patients.find((x) => x.id === id); return p ? `${p.patient_code} — ${p.first_name} ${p.last_name}` : 'Patient'; };
  return (
    <div className="space-y-6">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Droplets className="h-6 w-6" />Transfusion Board</h1><p className="text-sm text-muted-foreground">Consent-gated transfusion intake, documented lifecycle and reaction reporting. Compatibility is never inferred.</p></div><button onClick={() => void load()} className="self-start rounded-md border p-2" aria-label="Refresh"><RefreshCw className="h-4 w-4" /></button></header>
      <form onSubmit={create} className="rounded-xl border bg-card p-4 grid gap-3 md:grid-cols-2 lg:grid-cols-5">
        <select required value={form.patientId} onChange={(e) => setForm({ ...form, patientId: e.target.value })} className="w-full rounded-md border bg-background p-2 text-sm"><option value="">Select patient</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.patient_code} — {p.first_name} {p.last_name}</option>)}</select>
        <input required value={form.bloodProduct} onChange={(e) => setForm({ ...form, bloodProduct: e.target.value })} placeholder="Blood product" className="w-full rounded-md border bg-background p-2 text-sm" />
        <input required value={form.unitIdentifier} onChange={(e) => setForm({ ...form, unitIdentifier: e.target.value })} placeholder="Unit identifier" className="w-full rounded-md border bg-background p-2 text-sm" />
        <input value={form.bloodGroup} onChange={(e) => setForm({ ...form, bloodGroup: e.target.value })} placeholder="Recorded blood group" className="w-full rounded-md border bg-background p-2 text-sm" />
        <div className="flex flex-wrap items-center gap-3 md:col-span-2 lg:col-span-1"><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.consentConfirmed} onChange={(e) => setForm({ ...form, consentConfirmed: e.target.checked })} /> Consent confirmed</label><button disabled={busy} className="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground disabled:opacity-50">{busy ? 'Saving…' : 'Schedule'}</button></div>
      </form>
      <div className="grid gap-3">{rows.map((r) => <article key={r.id} className="rounded-xl border bg-card p-4"><div className="flex flex-wrap justify-between gap-3"><div className="min-w-0"><h2 className="font-semibold break-words">{patient(r.patient_id)}</h2><p className="text-sm break-words">{r.blood_product} · unit {r.unit_identifier}</p><p className="text-xs text-muted-foreground">Blood group: {r.blood_group || 'Not recorded'} · {r.status}</p></div><div className="flex flex-wrap gap-2 w-full sm:w-auto"><select disabled={busy || ['completed', 'cancelled'].includes(r.status)} value="" onChange={(e) => { if (e.target.value) void transition(r.id, e.target.value); }} className="w-full sm:w-auto rounded-md border bg-background px-2 py-1 text-sm"><option value="">Change status…</option>{statuses.filter((s) => s !== r.status).map((s) => <option key={s}>{s}</option>)}</select><button disabled={busy} onClick={() => void reaction(r.id)} className="rounded-md border px-2 py-1 text-sm inline-flex items-center gap-1"><AlertTriangle className="h-3 w-3" />Reaction</button></div></div>{r.reaction_observed && <p className="mt-2 text-sm text-destructive">Reaction documented: {r.reaction_notes || 'Details not recorded'}</p>}</article>)}{!rows.length && <p className="text-sm text-muted-foreground">No transfusion records found.</p>}</div>
    </div>
  );
}
