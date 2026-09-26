import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { FormEvent, useCallback, useEffect, useState } from 'react';
import { CalendarClock, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { searchPatientDirectory } from '@/lib/patientDirectory';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import { canTransitionWorkflow, getAllowedWorkflowTransitions, normalizeWorkflowStatus } from '@/lib/workflowTransitions';

type Row = { id: string; patient_id: string; procedure_name: string; theatre_name: string | null; scheduled_start: string | null; urgency: string; status: string; anesthetist_id: string | null };
type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
type Officer = { id: string; full_name: string | null; specialization: string | null };
const statuses = ['requested', 'approved', 'scheduled', 'in_progress', 'completed', 'postponed', 'cancelled'];

export default function TheatreBoard() {
  const [rows, setRows] = useState<Row[]>([]); const [patients, setPatients] = useState<Patient[]>([]); const [officers, setOfficers] = useState<Officer[]>([]); const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({ patientId: '', procedureName: '', scheduledStart: '', theatreName: '', urgency: 'elective' });
  const load = useCallback(async () => {
    const [workspace, p] = await Promise.all([
      getOperationalWorkspace('theatre', 150),
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
    const nextStatus = normalizeWorkflowStatus(status);
    const current = rows.find((row) => row.id === id)?.status;
    if (!current || !canTransitionWorkflow('theatre', current, nextStatus)) { toast({ title: 'Invalid workflow transition', description: 'Choose the next permitted theatre status.', variant: 'destructive' }); return; }
    setBusy(true); const { error } = await (supabase as any).rpc('transition_theatre_case', { _case_id: id, _status: nextStatus, _cancellation_reason: nextStatus === 'cancelled' || nextStatus === 'postponed' ? 'Status changed from theatre board' : null }); setBusy(false);
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
    <OperationalWorklistShell
      icon={CalendarClock}
      eyebrow="Surgical services"
      title="Theatre"
      description="Theatre intake, scheduling, anesthetist assignment and controlled clinical transitions."
      actions={<button type="button" onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4" /> Refresh</button>}
      counters={[
        { label: "Active cases", value: rows.filter((r) => !["completed","cancelled"].includes(r.status)).length, tone: "text-primary", surface: "bg-primary/5" },
        { label: "Scheduled", value: rows.filter((r) => r.status === "scheduled").length, tone: "text-info", surface: "bg-info/5" },
        { label: "In progress", value: rows.filter((r) => r.status === "in_progress").length, tone: "text-success", surface: "bg-success/5" },
        { label: "Urgent", value: rows.filter((r) => ["urgent","emergency"].includes(r.urgency)).length, tone: "text-warning", surface: "bg-warning/5" },
      ]}
      beforeList={
        <form onSubmit={createCase} className="card-medical p-5 sm:p-6 grid gap-4 lg:grid-cols-[1.3fr_1.5fr_1.2fr_1fr_1fr_auto]">
          <label className="space-y-1 text-sm"><span className="font-medium">Patient</span><select aria-label="Patient for theatre case" required value={form.patientId} onChange={(e) => setForm({ ...form, patientId: e.target.value })} className="input-medical w-full"><option value="">Select patient</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.patient_code} — {p.first_name} {p.last_name}</option>)}</select></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Procedure</span><input aria-label="Procedure name" required value={form.procedureName} onChange={(e) => setForm({ ...form, procedureName: e.target.value })} placeholder="Procedure" className="input-medical w-full" /></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Scheduled start</span><input aria-label="Scheduled start" required type="datetime-local" value={form.scheduledStart} onChange={(e) => setForm({ ...form, scheduledStart: e.target.value })} className="input-medical w-full" /></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Theatre</span><input aria-label="Theatre name" value={form.theatreName} onChange={(e) => setForm({ ...form, theatreName: e.target.value })} placeholder="Theatre" className="input-medical w-full" /></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Urgency</span><select aria-label="Theatre case urgency" value={form.urgency} onChange={(e) => setForm({ ...form, urgency: e.target.value })} className="input-medical w-full"><option value="elective">Elective</option><option value="urgent">Urgent</option><option value="emergency">Emergency</option></select></label>
          <button type="submit" disabled={busy} className="btn-primary self-end disabled:opacity-50">{busy ? "Saving…" : "Schedule case"}</button>
        </form>
      }
      listTitle="Theatre case worklist"
      listDescription="Review scheduled procedures, clinical urgency and anaesthesia assignment."
      listMeta={`${rows.length} case${rows.length === 1 ? "" : "s"}`}
      empty={!rows.length}
      emptyTitle="No theatre cases found"
      emptyDescription="Schedule a theatre case above to begin the surgical workflow."
    >
      {rows.map((r) => { const a = officer(r.anesthetist_id); return (
        <article key={r.id} className="px-5 py-4 transition-colors hover:bg-muted/30">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div className="min-w-0">
              <p className="font-medium break-words">{patient(r.patient_id)}</p>
              <p className="mt-1 text-sm break-words">{r.procedure_name} · {r.theatre_name || "Theatre not recorded"}</p>
              <div className="mt-2 flex flex-wrap gap-2 text-xs text-muted-foreground">
                <span>{r.scheduled_start ? new Date(r.scheduled_start).toLocaleString() : "Time not recorded"}</span>
                <span className="rounded-full bg-muted px-2 py-1 capitalize">{r.urgency}</span>
                <span className="rounded-full bg-primary/10 px-2 py-1 text-primary capitalize">{r.status.replaceAll("_"," ")}</span>
                <span>Anesthetist: {a?.full_name || a?.specialization || "Not assigned"}</span>
              </div>
            </div>
            <div className="flex flex-col gap-2 sm:flex-row">
              <select aria-label={`Change status for ${patient(r.patient_id)}`} disabled={busy || ["completed","cancelled"].includes(r.status)} value="" onChange={(e) => { if (e.target.value) void transition(r.id, e.target.value); }} className="input-medical text-sm sm:w-52"><option value="">Change status…</option>{getAllowedWorkflowTransitions('theatre', r.status).map((s) => <option key={s}>{s}</option>)}</select>
              <select aria-label={`Assign anesthetist for ${patient(r.patient_id)}`} disabled={busy || ["completed","cancelled"].includes(r.status) || anesthesiaOfficers.length === 0} value="" onChange={(e) => { if (e.target.value) void assignAnesthetist(r.id, e.target.value); }} className="input-medical text-sm sm:w-52"><option value="">Assign anesthetist…</option>{anesthesiaOfficers.map((o) => <option key={o.id} value={o.id}>{o.full_name || o.specialization || o.id}</option>)}</select>
            </div>
          </div>
        </article>
      ); })}
    </OperationalWorklistShell>
  );
}
