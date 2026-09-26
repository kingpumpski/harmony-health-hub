import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { FormEvent, useCallback, useEffect, useState } from 'react';
import { AlertTriangle, Droplets, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { searchPatientDirectory } from '@/lib/patientDirectory';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';

type Row = { id: string; patient_id: string; blood_product: string; unit_identifier: string; blood_group: string | null; status: string; reaction_observed: boolean; reaction_notes: string | null };
type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
const statuses = ['planned', 'issued', 'running', 'completed', 'stopped', 'cancelled'];

export default function TransfusionBoard() {
  const [rows, setRows] = useState<Row[]>([]); const [patients, setPatients] = useState<Patient[]>([]); const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({ patientId: '', bloodProduct: '', unitIdentifier: '', bloodGroup: '', consentConfirmed: false });
  const load = useCallback(async () => {
    const [workspace, p] = await Promise.all([
      getOperationalWorkspace('transfusion', 150),
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
    <OperationalWorklistShell
      icon={Droplets}
      eyebrow="Transfusion services"
      title="Transfusion"
      description="Consent-gated transfusion intake, documented lifecycle and reaction reporting. Compatibility is never inferred."
      actions={<button type="button" onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4" /> Refresh</button>}
      counters={[
        { label: "Active records", value: rows.filter((r) => !["completed","cancelled"].includes(r.status)).length, tone: "text-primary", surface: "bg-primary/5" },
        { label: "Planned", value: rows.filter((r) => r.status === "planned").length, tone: "text-info", surface: "bg-info/5" },
        { label: "Running", value: rows.filter((r) => r.status === "running").length, tone: "text-success", surface: "bg-success/5" },
        { label: "Reactions", value: rows.filter((r) => r.reaction_observed).length, tone: "text-critical", surface: "bg-critical/5" },
      ]}
      beforeList={
        <form onSubmit={create} className="card-medical p-5 sm:p-6 grid gap-4 md:grid-cols-2 lg:grid-cols-5">
          <label className="space-y-1 text-sm"><span className="font-medium">Patient</span><select required value={form.patientId} onChange={(e) => setForm({ ...form, patientId: e.target.value })} className="input-medical w-full"><option value="">Select patient</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.patient_code} — {p.first_name} {p.last_name}</option>)}</select></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Blood product</span><input required value={form.bloodProduct} onChange={(e) => setForm({ ...form, bloodProduct: e.target.value })} placeholder="Blood product" className="input-medical w-full" /></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Unit identifier</span><input required value={form.unitIdentifier} onChange={(e) => setForm({ ...form, unitIdentifier: e.target.value })} placeholder="Unit identifier" className="input-medical w-full" /></label>
          <label className="space-y-1 text-sm"><span className="font-medium">Recorded blood group</span><input value={form.bloodGroup} onChange={(e) => setForm({ ...form, bloodGroup: e.target.value })} placeholder="Recorded blood group" className="input-medical w-full" /></label>
          <div className="flex flex-wrap items-end gap-3"><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.consentConfirmed} onChange={(e) => setForm({ ...form, consentConfirmed: e.target.checked })} /> Consent confirmed</label><button type="submit" disabled={busy} className="btn-primary disabled:opacity-50">{busy ? "Saving…" : "Schedule"}</button></div>
        </form>
      }
      listTitle="Transfusion worklist"
      listDescription="Monitor lifecycle status and document reactions without inferring compatibility."
      listMeta={`${rows.length} record${rows.length === 1 ? "" : "s"}`}
      empty={!rows.length}
      emptyTitle="No transfusion records found"
      emptyDescription="Create a transfusion record above after documented consent is confirmed."
    >
      {rows.map((r) => (
        <article key={r.id} className="px-5 py-4 transition-colors hover:bg-muted/30">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div className="min-w-0">
              <p className="font-medium break-words">{patient(r.patient_id)}</p>
              <p className="mt-1 text-sm break-words">{r.blood_product} · unit {r.unit_identifier}</p>
              <div className="mt-2 flex flex-wrap gap-2 text-xs text-muted-foreground">
                <span>Blood group: {r.blood_group || "Not recorded"}</span>
                <span className="rounded-full bg-primary/10 px-2 py-1 text-primary capitalize">{r.status.replaceAll("_"," ")}</span>
              </div>
            </div>
            <div className="flex flex-col gap-2 sm:flex-row">
              <select aria-label={`Change status for ${patient(r.patient_id)}`} disabled={busy || ["completed","cancelled"].includes(r.status)} value="" onChange={(e) => { if (e.target.value) void transition(r.id, e.target.value); }} className="input-medical text-sm sm:w-48"><option value="">Change status…</option>{statuses.filter((s) => s !== r.status).map((s) => <option key={s}>{s}</option>)}</select>
              <button type="button" disabled={busy} onClick={() => void reaction(r.id)} className="btn-secondary inline-flex items-center gap-1 text-sm"><AlertTriangle className="h-3 w-3" />Reaction</button>
            </div>
          </div>
          {r.reaction_observed && <p className="mt-3 rounded-xl border border-critical/30 bg-critical/5 px-3 py-2 text-sm text-critical">Reaction documented: {r.reaction_notes || "Details not recorded"}</p>}
        </article>
      ))}
    </OperationalWorklistShell>
  );
}
