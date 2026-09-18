import { FormEvent, useCallback, useEffect, useState } from 'react';
import { CalendarClock, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { searchPatientDirectory } from '@/lib/patientDirectory';

type Row = { id: string; patient_id: string; procedure_name: string; theatre_name: string | null; scheduled_start: string | null; urgency: string; status: string; anesthetist_id: string | null };
type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
type Officer = { id: string; full_name: string | null; specialization: string | null };
const statuses = ['requested', 'approved', 'scheduled', 'in_progress', 'completed', 'postponed', 'cancelled'];

export default function TheatreBoard() {
  const [rows, setRows] = useState<Row[]>([]); const [patients, setPatients] = useState<Patient[]>([]); const [officers, setOfficers] = useState<Officer[]>([]); const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({ patientId: '', procedureName: '', scheduledStart: '', theatreName: '', urgency: 'elective' });
  const load = useCallback(async () => {
    const [workspace, p] = await Promise.all([
      supabase.rpc('get_operational_workspace', { _module: 'theatre', _limit: 150 }),
      searchPatientDirectory('', 500),
    ]);
    const workspaceData = (workspace.data ?? {}) as any;
    const r = { data: workspaceData.cases ?? [], error: workspace.error };
    const o = { data: workspaceData.profiles ?? [], error: workspace.error };
    if (p.error || r.error || o.error) toast({ title: 'Unable to load theatre board', description: (p.error || r.error || o.error)?.message, variant: 'destructive' });
    setPatients((p.data ?? []) as Patient[]); setRows((r.data ?? []) as Row[]); setOfficers((o.data ?? []) as Officer[]);
  }, []);
  useEffect(() => { void load(); }, [load]);
  const createCase = async (event: FormEvent) => {
    event.preventDefault(); if (!form.patientId || !form.procedureName.trim() || !form.scheduledStart) { toast({ title: 'Patient, procedure and scheduled start are required', variant: 'destructive' }); return; }
    setBusy(true); const { error } = await (supabase as any).rpc('create_theatre_case', { _patient_id: form.patientId, _procedure_name: form.procedureName.trim(), _scheduled_start: new Date(form.scheduledStart).toISOString(), _theatre_name: form.theatreName.trim() || null, _urgency: form.urgency, _surgeon_id: null, _anesthetist_id: null, _encounter_id: null }); setBusy(false);
    if (error) { toast({ title: 'Theatre case creation failed', description: error.message, variant: 'destructive' }); return; }
    setForm({ patientId: '', procedureName: '', scheduledStart: '', theatreName: '', urgency: 'elective' }); toast({ title: 'Theatre case registered' }); void load();
  };
  const transition = async (id: string, status: string) => {
    setBusy(true); const { error } = await (supabase as any).rpc('transition_theatre_case', { _case_id: id, _status: status, _cancellation_reason: status === 'cancelled' || status === 'postponed' ? 'Status changed from theatre board' : null }); setBusy(false);
    if (error) toast({ title: 'Transition failed', description: error.message, variant: 'destructive' }); else { toast({ title: 'Theatre status updated' }); void load(); }
  };
  const assignAnesthetist = async (id: string, officerId: string) => {
    if (!officerId) return; setBusy(true); const { error } = await (supabase as any).rpc('assign_theatre_anesthetist', { _case_id: id, _anesthetist_id: officerId }); setBusy(false);
    if (error) toast({ title: 'Assignment failed', description: error.message, variant: 'destructive' }); else { toast({ title: 'Anesthetist assigned' }); void load(); }
  };
  const patient = (id: string) => { const p = patients.find((x) => x.id === id); return p ? `${p.patient_code} — ${p.first_name} ${p.last_name}` : 'Patient'; };
  const officer = (id: string | null) => officers.find((x) => x.id === id);
  const anesthesiaOfficers = officers.filter((o) => /anesth|anaesth/i.test(`${o.specialization || ''}`));
  return (
    <div className="space-y-6">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><CalendarClock className="h-6 w-6" />Theatre Board</h1><p className="text-sm text-muted-foreground">Theatre intake, scheduling, anesthetist assignment and controlled clinical transitions.</p></div><button onClick={() => void load()} className="self-start rounded-md border p-2" aria-label="Refresh"><RefreshCw className="h-4 w-4" /></button></header>
      <form onSubmit={createCase} className="rounded-xl border bg-card p-4 grid gap-3 lg:grid-cols-[1.3fr_1.5fr_1.2fr_1fr_1fr_auto]">
        <select required value={form.patientId} onChange={(e) => setForm({ ...form, patientId: e.target.value })} className="w-full rounded-md border bg-background p-2 text-sm"><option value="">Select patient</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.patient_code} — {p.first_name} {p.last_name}</option>)}</select>
        <input required value={form.procedureName} onChange={(e) => setForm({ ...form, procedureName: e.target.value })} placeholder="Procedure" className="w-full rounded-md border bg-background p-2 text-sm" />
        <input required type="datetime-local" value={form.scheduledStart} onChange={(e) => setForm({ ...form, scheduledStart: e.target.value })} className="w-full rounded-md border bg-background p-2 text-sm" />
        <input value={form.theatreName} onChange={(e) => setForm({ ...form, theatreName: e.target.value })} placeholder="Theatre" className="w-full rounded-md border bg-background p-2 text-sm" />
        <select value={form.urgency} onChange={(e) => setForm({ ...form, urgency: e.target.value })} className="w-full rounded-md border bg-background p-2 text-sm"><option value="elective">Elective</option><option value="urgent">Urgent</option><option value="emergency">Emergency</option></select>
        <button disabled={busy} className="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground disabled:opacity-50">{busy ? 'Saving…' : 'Schedule case'}</button>
      </form>
      <div className="grid gap-3">{rows.map((r) => { const a = officer(r.anesthetist_id); return <article key={r.id} className="rounded-xl border bg-card p-4"><div className="flex flex-wrap justify-between gap-3"><div className="min-w-0"><h2 className="font-semibold break-words">{patient(r.patient_id)}</h2><p className="text-sm break-words">{r.procedure_name} · {r.theatre_name || 'Theatre not recorded'}</p><p className="text-xs text-muted-foreground">{r.scheduled_start ? new Date(r.scheduled_start).toLocaleString() : 'Time not recorded'} · {r.urgency} · {r.status}</p><p className="text-xs text-muted-foreground mt-1">Anesthetist: {a?.full_name || a?.specialization || 'Not assigned'}</p></div><div className="flex flex-col sm:flex-row gap-2 w-full sm:w-auto"><select disabled={busy || ['completed', 'cancelled'].includes(r.status)} value="" onChange={(e) => { if (e.target.value) void transition(r.id, e.target.value); }} className="w-full sm:w-auto rounded-md border bg-background px-2 py-1 text-sm"><option value="">Change status…</option>{statuses.filter((s) => s !== r.status).map((s) => <option key={s}>{s}</option>)}</select><select disabled={busy || ['completed', 'cancelled'].includes(r.status) || anesthesiaOfficers.length === 0} value="" onChange={(e) => { if (e.target.value) void assignAnesthetist(r.id, e.target.value); }} className="w-full sm:w-auto rounded-md border bg-background px-2 py-1 text-sm"><option value="">Assign anesthetist…</option>{anesthesiaOfficers.map((o) => <option key={o.id} value={o.id}>{o.full_name || o.specialization || o.id}</option>)}</select></div></div></article>; })}{!rows.length && <p className="text-sm text-muted-foreground">No theatre cases found.</p>}</div>
    </div>
  );
}
