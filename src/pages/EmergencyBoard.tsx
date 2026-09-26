import { FormEvent, useCallback, useEffect, useState } from 'react';
import { RefreshCw, Siren } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

type Row = { id: string; patient_id: string | null; chief_complaint: string; acuity: string; arrival_mode: string | null; assigned_officer: string | null; status: string; arrival_time: string };
type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
const statuses = ['waiting', 'triage', 'treatment', 'observation', 'admitted', 'discharged', 'referred', 'left_without_being_seen', 'cancelled'];
const acuities = ['resuscitation', 'emergency', 'urgent', 'less_urgent', 'non_urgent'];

export default function EmergencyBoard() {
  const [rows, setRows] = useState<Row[]>([]);
  const [patients, setPatients] = useState<Patient[]>([]);
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({ patientId: '', chiefComplaint: '', acuity: 'urgent', arrivalMode: 'walk_in' });
  const load = useCallback(async () => {
    const { data, error } = await (supabase as any).rpc('get_emergency_workspace', { _limit: 300 });
    if (error) {
      toast({ title: 'Unable to load emergency queue', description: error.message, variant: 'destructive' });
      return;
    }
    const workspace = (data ?? {}) as { patients?: Patient[]; cases?: Row[] };
    setPatients(workspace.patients ?? []);
    setRows(workspace.cases ?? []);
  }, []);
  useEffect(() => { void load(); }, [load]);
  const createCase = async (event: FormEvent) => {
    event.preventDefault();
    if (!form.patientId || !form.chiefComplaint.trim()) { toast({ title: 'Patient and chief complaint are required', variant: 'destructive' }); return; }
    setBusy(true);
    const { error } = await (supabase as any).rpc('create_emergency_case', { _patient_id: form.patientId, _chief_complaint: form.chiefComplaint.trim(), _acuity: form.acuity, _arrival_mode: form.arrivalMode, _assigned_officer: null });
    setBusy(false);
    if (error) { toast({ title: 'Emergency intake failed', description: error.message, variant: 'destructive' }); return; }
    setForm({ patientId: '', chiefComplaint: '', acuity: 'urgent', arrivalMode: 'walk_in' }); toast({ title: 'Emergency case registered' }); void load();
  };
  const transition = async (id: string, status: string) => {
    setBusy(true);
    const { error } = await (supabase as any).rpc('transition_emergency_case', { _case_id: id, _status: status, _disposition: status === 'discharged' ? 'Discharged from emergency' : status === 'referred' ? 'Referred for further care' : status === 'admitted' ? 'Admitted for further care' : null });
    setBusy(false);
    if (error) toast({ title: 'Emergency transition failed', description: error.message, variant: 'destructive' }); else { toast({ title: 'Emergency status updated' }); void load(); }
  };
  const assign = async (id: string) => {
    setBusy(true); const { error } = await (supabase as any).rpc('assign_emergency_officer', { _case_id: id, _officer_id: null }); setBusy(false);
    if (error) toast({ title: 'Assignment failed', description: error.message, variant: 'destructive' }); else { toast({ title: 'Case assigned to you' }); void load(); }
  };
  const patient = (id: string | null) => { const p = patients.find((x) => x.id === id); return p ? `${p.patient_code} — ${p.first_name} ${p.last_name}` : 'Unregistered / patient not recorded'; };
  return (
    <OperationalWorklistShell
      icon={Siren}
      eyebrow="Emergency care"
      title="Emergency"
      description="Emergency intake, officer assignment and controlled disposition workflow."
      actions={<button type="button" onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4" /> Refresh</button>}
      counters={[
        { label: "Active cases", value: rows.filter((r) => !["discharged","referred","left_without_being_seen","cancelled"].includes(r.status)).length, tone: "text-primary", surface: "bg-primary/5" },
        { label: "Resuscitation", value: rows.filter((r) => r.acuity === "resuscitation").length, tone: "text-critical", surface: "bg-critical/5" },
        { label: "Waiting / triage", value: rows.filter((r) => ["waiting","triage"].includes(r.status)).length, tone: "text-warning", surface: "bg-warning/5" },
        { label: "In treatment", value: rows.filter((r) => r.status === "treatment").length, tone: "text-success", surface: "bg-success/5" },
      ]}
      beforeList={
        <form onSubmit={createCase} className="card-medical p-5 sm:p-6 grid gap-4 lg:grid-cols-[1.3fr_2fr_1fr_1fr_auto]">
          <label className="space-y-1 text-sm"><span className="font-medium">Patient</span><select aria-label="Patient for emergency intake" required value={form.patientId} onChange={(e) => setForm({ ...form, patientId: e.target.value })} className="input-medical w-full"><option value="">Select patient</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.patient_code} — {p.first_name} {p.last_name}</option>)}</select></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Chief complaint</span><input aria-label="Chief complaint or presenting problem" required value={form.chiefComplaint} onChange={(e) => setForm({ ...form, chiefComplaint: e.target.value })} placeholder="Chief complaint / presenting problem" className="input-medical w-full" /></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Acuity</span><select aria-label="Emergency acuity" value={form.acuity} onChange={(e) => setForm({ ...form, acuity: e.target.value })} className="input-medical w-full">{acuities.map((item) => <option key={item}>{item}</option>)}</select></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Arrival mode</span><select aria-label="Arrival mode" value={form.arrivalMode} onChange={(e) => setForm({ ...form, arrivalMode: e.target.value })} className="input-medical w-full"><option value="walk_in">Walk-in</option><option value="ambulance">Ambulance</option><option value="referral">Referral</option><option value="other">Other</option></select></label>
          <button type="submit" disabled={busy} className="btn-primary self-end disabled:opacity-50">{busy ? "Saving…" : "Register case"}</button>
        </form>
      }
      listTitle="Active emergency queue"
      listDescription="Select a case to review its current patient context and controlled workflow actions."
      listMeta={`${rows.length} case${rows.length === 1 ? "" : "s"}`}
      empty={!rows.length}
      emptyTitle="No emergency cases found"
      emptyDescription="Register an emergency case above to begin the controlled workflow."
    >
      {rows.map((r) => (
        <article key={r.id} className="px-5 py-4 transition-colors hover:bg-muted/30">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div className="min-w-0">
              <p className="font-medium truncate">{patient(r.patient_id)}</p>
              <p className="mt-1 text-sm">{r.chief_complaint}</p>
              <div className="mt-2 flex flex-wrap gap-2 text-xs text-muted-foreground">
                <span className="rounded-full bg-muted px-2 py-1 capitalize">{r.acuity.replaceAll("_", " ")}</span>
                <span className="rounded-full bg-muted px-2 py-1">{r.arrival_mode || "Not recorded"}</span>
                <span className="rounded-full bg-primary/10 px-2 py-1 text-primary capitalize">{r.status.replaceAll("_", " ")}</span>
                <span>{new Date(r.arrival_time).toLocaleString()}</span>
              </div>
            </div>
            <div className="flex flex-col gap-2 sm:flex-row">
              <button type="button" aria-label={`Assign ${patient(r.patient_id)} to me`} disabled={busy || !!r.assigned_officer} onClick={() => void assign(r.id)} className="btn-secondary text-sm disabled:opacity-50">{r.assigned_officer ? "Assigned" : "Assign to me"}</button>
              <select aria-label={`Change status for ${patient(r.patient_id)}`} disabled={busy || ["discharged","referred","left_without_being_seen","cancelled"].includes(r.status)} value="" onChange={(e) => { if (e.target.value) void transition(r.id, e.target.value); }} className="input-medical text-sm sm:w-52"><option value="">Change status…</option>{statuses.filter((s) => s !== r.status).map((s) => <option key={s} value={s}>{s.replaceAll("_", " ")}</option>)}</select>
            </div>
          </div>
        </article>
      ))}
    </OperationalWorklistShell>
  );
}
