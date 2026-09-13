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
    const [p, r] = await Promise.all([
      supabase.from('patients').select('id,patient_code,first_name,last_name').limit(500),
      supabase.from('emergency_cases').select('id,patient_id,chief_complaint,acuity,arrival_mode,assigned_officer,status,arrival_time').order('arrival_time', { ascending: false }).limit(150),
    ]);
    if (p.error || r.error) toast({ title: 'Unable to load emergency queue', description: (p.error || r.error)?.message, variant: 'destructive' });
    setPatients((p.data ?? []) as Patient[]); setRows((r.data ?? []) as Row[]);
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
    <div className="space-y-6">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Siren className="h-6 w-6" />Emergency Board</h1><p className="text-sm text-muted-foreground">Emergency intake, officer assignment and controlled disposition workflow.</p></div><button onClick={() => void load()} className="self-start rounded-md border p-2" aria-label="Refresh"><RefreshCw className="h-4 w-4" /></button></header>
      <form onSubmit={createCase} className="rounded-xl border bg-card p-4 grid gap-3 lg:grid-cols-[1.3fr_2fr_1fr_1fr_auto]">
        <select required value={form.patientId} onChange={(e) => setForm({ ...form, patientId: e.target.value })} className="w-full rounded-md border bg-background p-2 text-sm"><option value="">Select patient</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.patient_code} — {p.first_name} {p.last_name}</option>)}</select>
        <input required value={form.chiefComplaint} onChange={(e) => setForm({ ...form, chiefComplaint: e.target.value })} placeholder="Chief complaint / presenting problem" className="w-full rounded-md border bg-background p-2 text-sm" />
        <select value={form.acuity} onChange={(e) => setForm({ ...form, acuity: e.target.value })} className="w-full rounded-md border bg-background p-2 text-sm">{acuities.map((item) => <option key={item}>{item}</option>)}</select>
        <select value={form.arrivalMode} onChange={(e) => setForm({ ...form, arrivalMode: e.target.value })} className="w-full rounded-md border bg-background p-2 text-sm"><option value="walk_in">Walk-in</option><option value="ambulance">Ambulance</option><option value="referral">Referral</option><option value="other">Other</option></select>
        <button disabled={busy} className="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground disabled:opacity-50">{busy ? 'Saving…' : 'Register case'}</button>
      </form>
      <div className="grid gap-3">{rows.map((r) => <article key={r.id} className="rounded-xl border bg-card p-4"><div className="flex flex-wrap justify-between gap-3"><div className="min-w-0"><h2 className="font-semibold truncate">{patient(r.patient_id)}</h2><p className="text-sm break-words">{r.chief_complaint}</p><p className="text-xs text-muted-foreground">{r.acuity} · {r.arrival_mode || 'Not recorded'} · {r.status} · {new Date(r.arrival_time).toLocaleString()}</p></div><div className="flex flex-wrap gap-2 w-full sm:w-auto"><button disabled={busy || !!r.assigned_officer} onClick={() => void assign(r.id)} className="rounded-md border px-2 py-1 text-sm disabled:opacity-50">{r.assigned_officer ? 'Assigned' : 'Assign to me'}</button><select disabled={busy || ['discharged', 'referred', 'left_without_being_seen', 'cancelled'].includes(r.status)} value="" onChange={(e) => { if (e.target.value) void transition(r.id, e.target.value); }} className="w-full sm:w-auto rounded-md border bg-background px-2 py-1 text-sm"><option value="">Change status…</option>{statuses.filter((s) => s !== r.status).map((s) => <option key={s} value={s}>{s.replaceAll('_', ' ')}</option>)}</select></div></div></article>)}{!rows.length && <p className="text-sm text-muted-foreground">No emergency cases found.</p>}</div>
    </div>
  );
}
