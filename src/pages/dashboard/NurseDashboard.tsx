import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Activity, AlertTriangle, BedDouble, BellRing, ClipboardList, FileText, HeartPulse, Pill, RefreshCw, Syringe, Users, X, Save } from 'lucide-react';
import { Link } from 'react-router-dom';
import StatCard from '@/components/ui/StatCard';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { playWorkflowSound, playWorkflowSoundLoop } from '@/lib/workflowFeedback';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
type DashboardRow = Record<string, any>;

const statusTone = (status: string) => status === 'critical' ? 'bg-critical/5 border-l-2 border-l-critical' : status === 'attention' ? 'bg-warning/5 border-l-2 border-l-warning' : '';

export default function NurseDashboard() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [admissions, setAdmissions] = useState<DashboardRow[]>([]);
  const [medications, setMedications] = useState<DashboardRow[]>([]);
  const [handovers, setHandovers] = useState<DashboardRow[]>([]);
  const [triage, setTriage] = useState<DashboardRow[]>([]);
  const [queue, setQueue] = useState<DashboardRow[]>([]);
  const [workflowNotifications, setWorkflowNotifications] = useState<DashboardRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<'all' | 'critical' | 'attention'>('all');
  const [noteTarget, setNoteTarget] = useState<DashboardRow | null>(null);
  const [noteForm, setNoteForm] = useState({ note_text: '', assessment: '', intervention: '', evaluation: '' });
  const [noteSaving, setNoteSaving] = useState(false);
  const [medTarget, setMedTarget] = useState<DashboardRow | null>(null);
  const [medAlertEnabled, setMedAlertEnabled] = useState(false);
  const stopMedicationAlertRef = useRef<(() => void) | null>(null);

  const load = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    setError(null);
    const { data, error } = await supabase.functions.invoke('ai-clinical-assist', { body: { mode: 'nurse_dashboard' } });
    if (error || data?.error) {
      setError(data?.error ?? error?.message ?? 'Workspace unavailable');
      setPatients([]); setAdmissions([]); setMedications([]); setHandovers([]); setTriage([]); setQueue([]); setWorkflowNotifications([]);
      toast.error('Nursing dashboard refresh: ' + (data?.error ?? error?.message ?? 'Workspace unavailable'));
    } else {
      setPatients((data?.patients ?? []) as Patient[]);
      setAdmissions((data?.admissions ?? []) as DashboardRow[]);
      setMedications((data?.medications ?? []) as DashboardRow[]);
      setHandovers((data?.handovers ?? []) as DashboardRow[]);
      setTriage((data?.triage ?? []) as DashboardRow[]);
      setQueue((data?.queue ?? []) as DashboardRow[]);
      const { data: notifications, error: notificationError } = await (supabase as any).rpc('get_workflow_notifications', { _limit: 100 });
      if (notificationError) { setError(notificationError.message); setWorkflowNotifications([]); } else setWorkflowNotifications((Array.isArray(notifications) ? notifications : []) as DashboardRow[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    const evaluate = () => {
      const now = Date.now();
      const attention = medications.filter((m) => {
        if (m.status !== 'scheduled' || m.locked_at || !m.scheduled_at) return false;
        const dueAt = new Date(m.scheduled_at).getTime();
        const dueWindow = Number(m.due_window_minutes ?? 30) * 60_000;
        return dueAt >= now - dueWindow && dueAt <= now + 5 * 60_000;
      });
      if (medAlertEnabled && attention.length) {
        if (!stopMedicationAlertRef.current) stopMedicationAlertRef.current = playWorkflowSoundLoop('critical');
        try { navigator.vibrate?.([400, 150, 400, 150, 700]); } catch {}
        if ('Notification' in window && Notification.permission === 'granted') {
          const first = attention[0];
          const person = patients.find((item) => item.id === first.patient_id);
          const name = person ? `${person.first_name} ${person.last_name}` : 'the patient';
          new Notification('Medication due', { body: `${attention.length} medication dose(s) require attention for ${name}.`, tag: 'hms-medication-due', renotify: true });
        }
      } else if (stopMedicationAlertRef.current) {
        stopMedicationAlertRef.current();
        stopMedicationAlertRef.current = null;
      }
    };
    evaluate();
    const timer = window.setInterval(evaluate, 15000);
    return () => {
      window.clearInterval(timer);
      if (stopMedicationAlertRef.current) { stopMedicationAlertRef.current(); stopMedicationAlertRef.current = null; }
    };
  }, [medications, medAlertEnabled, patients]);
  useEffect(() => {
    const channel = supabase.channel(`nurse-dashboard-${user?.id ?? 'station'}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'medication_administrations' }, () => { playWorkflowSound('info'); void load(true); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'department_queues' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'nursing_shift_handovers' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'triage_assessments' }, () => { playWorkflowSound('critical'); void load(true); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'admissions' }, () => { playWorkflowSound('info'); void load(true); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, () => { playWorkflowSound('info'); void load(true); })
      .subscribe();
    const timer = window.setInterval(() => void load(true), 60000);
    return () => { void supabase.removeChannel(channel); window.clearInterval(timer); };
  }, [load, user?.id]);

  const patientName = (id?: string) => {
    const p = patients.find(x => x.id === id);
    return p ? `${p.first_name} ${p.last_name}` : 'Patient';
  };
  const activeAdmissions = useMemo(() => admissions.filter(a => !a.discharged_at && a.status !== 'discharged'), [admissions]);
  const dueMeds = useMemo(() => medications.filter(m => m.status === 'scheduled' && !m.locked_at), [medications]);
  const overdueMeds = useMemo(() => dueMeds.filter(m => m.scheduled_at && new Date(m.scheduled_at).getTime() < Date.now()), [dueMeds]);
  const criticalPatients = useMemo(() => triage.filter(t => ['critical', 'urgent'].includes(String(t.priority ?? t.status ?? '').toLowerCase())).slice(0, 12), [triage]);
  const pendingHandovers = useMemo(() => handovers.filter(h => !h.acknowledged_at), [handovers]);
  const inpatientRows = useMemo(() => activeAdmissions.slice(0, 30).map(a => ({ ...a, status: criticalPatients.some(t => t.patient_id === a.patient_id) ? 'critical' : 'stable' })), [activeAdmissions, criticalPatients]);
  const unreadAdmissionAlerts = useMemo(() => workflowNotifications.filter(n => !n.is_read && /new inpatient admission/i.test(String(n.title ?? ''))), [workflowNotifications]);

  const refresh = () => { void load(); };
  const saveNursingNote = async () => {
    if (!noteTarget?.patient_id || !noteTarget?.id || !noteForm.note_text.trim()) {
      toast.error('Enter the nursing note before saving.');
      return;
    }
    setNoteSaving(true);
    const { error } = await (supabase as any).rpc('create_nursing_note', {
      _patient_id: noteTarget.patient_id,
      _note_text: noteForm.note_text.trim(),
      _note_type: 'progress',
      _assessment: noteForm.assessment.trim() || null,
      _intervention: noteForm.intervention.trim() || null,
      _evaluation: noteForm.evaluation.trim() || null,
      _encounter_id: null,
      _admission_id: noteTarget.id,
    });
    setNoteSaving(false);
    if (error) {
      toast.error(error.message ?? 'Unable to save nursing note');
      return;
    }
    toast.success('Nursing note saved to the current admission.');
    setNoteTarget(null);
    setNoteForm({ note_text: '', assessment: '', intervention: '', evaluation: '' });
  };

  return (
    <div className="space-y-6 animate-fade-in">
      {error && <div role="alert" className="rounded-xl border border-critical/30 bg-critical/5 p-4 flex flex-wrap items-center justify-between gap-3"><div><p className="font-semibold text-critical">Nursing dashboard data unavailable</p><p className="text-sm text-muted-foreground mt-1">{error}</p></div><button type="button" onClick={refresh} className="btn-secondary">Retry</button></div>}

      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-heading font-bold">Nursing Station</h1>
          <p className="text-muted-foreground">Live inpatient care, medication administration, handover and escalation workspace.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link to="/nursing-handover" className="btn-secondary"><FileText className="w-4 h-4" /> Nursing Handover</Link>
          <Link to="/vitals" className="btn-primary"><HeartPulse className="w-4 h-4" /> Record Vitals</Link>
          <button type="button" onClick={async () => {
            if ('Notification' in window && Notification.permission !== 'granted') {
              const permission = await Notification.requestPermission();
              if (permission !== 'granted') { toast.info('System medication notifications remain disabled.'); return; }
            }
            setMedAlertEnabled(true);
            playWorkflowSound('critical');
            toast.success('Medication alerts enabled for this nursing session.');
          }} className={cn('btn-secondary', medAlertEnabled && 'border-primary/40 bg-primary/5')}><Pill className="w-4 h-4" /> {medAlertEnabled ? 'Alerts enabled' : 'Enable med alerts'}</button>
          <button type="button" onClick={refresh} className="btn-ghost" aria-label="Refresh nursing dashboard"><RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} /></button>
        </div>
      </div>

      {unreadAdmissionAlerts.length > 0 && <div className="rounded-xl border border-info/30 bg-info/5 p-4 flex flex-wrap items-center justify-between gap-3 animate-pulse">
        <div className="flex items-center gap-3"><BellRing className="w-5 h-5 text-info" /><div><p className="font-semibold text-info">New inpatient admission</p><p className="text-sm text-muted-foreground">{unreadAdmissionAlerts.length} admission notification(s) require acknowledgement in the nursing workflow.</p></div></div>
        <Link to="/notifications" className="btn-secondary">Review admission alerts</Link>
      </div>}

      {criticalPatients.length > 0 && <div className="rounded-xl border border-critical/30 bg-critical/5 p-4 flex flex-wrap items-center justify-between gap-3 animate-pulse">
        <div className="flex items-center gap-3"><AlertTriangle className="w-5 h-5 text-critical" /><div><p className="font-semibold text-critical">Clinical attention required</p><p className="text-sm text-muted-foreground">{criticalPatients.length} recent critical/urgent triage record(s) require nursing review.</p></div></div>
        <Link to="/vitals" className="btn-secondary">Open vitals</Link>
      </div>}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
        <StatCard title="Active Inpatients" value={activeAdmissions.length} change="Open admissions" changeType="neutral" icon={BedDouble} iconColor="text-primary" />
        <StatCard title="Medications Due" value={dueMeds.length} change={`${overdueMeds.length} overdue`} changeType={overdueMeds.length ? 'negative' : 'neutral'} icon={Pill} iconColor="text-warning" />
        <StatCard title="Vitals / Escalations" value={criticalPatients.length} change="Critical or urgent" changeType={criticalPatients.length ? 'negative' : 'neutral'} icon={HeartPulse} iconColor="text-critical" />
        <StatCard title="Unacknowledged Handovers" value={pendingHandovers.length} change="Continuity actions" changeType="neutral" icon={ClipboardList} iconColor="text-info" />
        <StatCard title="Nursing Queue" value={queue.length} change="Waiting / claimed" changeType="neutral" icon={Users} iconColor="text-primary" />
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Link to="/nursing-handover" className="card-medical p-4 bg-info/5 hover:bg-info/10 transition-all hover:-translate-y-0.5"><BellRing className="w-4 h-4 mb-2" /><p className="text-xs text-muted-foreground">Handover</p><p className="text-2xl font-bold tabular-nums">{pendingHandovers.length}</p></Link>
        <Link to="/medications" className="card-medical p-4 bg-warning/5 hover:bg-warning/10 transition-all hover:-translate-y-0.5"><Syringe className="w-4 h-4 mb-2" /><p className="text-xs text-muted-foreground">Medication due</p><p className="text-2xl font-bold tabular-nums">{dueMeds.length}</p></Link>
        <Link to="/vitals" className="card-medical p-4 bg-critical/5 hover:bg-critical/10 transition-all hover:-translate-y-0.5"><Activity className="w-4 h-4 mb-2" /><p className="text-xs text-muted-foreground">Critical review</p><p className="text-2xl font-bold tabular-nums">{criticalPatients.length}</p></Link>
        <Link to="/ward-bed-board" className="card-medical p-4 bg-primary/5 hover:bg-primary/10 transition-all hover:-translate-y-0.5"><BedDouble className="w-4 h-4 mb-2" /><p className="text-xs text-muted-foreground">Ward / beds</p><p className="text-sm font-semibold mt-1">Open bed board →</p></Link>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <section className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border flex flex-wrap items-center justify-between gap-3">
            <div><h2 className="font-semibold">Current Inpatients</h2><p className="text-xs text-muted-foreground">Live admissions replace the former static demonstration list.</p></div>
            <div className="flex gap-2">{(['all', 'critical', 'attention'] as const).map(f => <button key={f} onClick={() => setFilter(f)} className={cn('px-3 py-1.5 rounded-lg text-sm font-medium capitalize', filter === f ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground')}>{f}</button>)}</div>
          </div>
          <div className="divide-y divide-border">
            {inpatientRows.filter(p => filter === 'all' || p.status === filter).map((patient, index) => {
              const person = patients.find((item) => item.id === patient.patient_id);
              const latestVital = triage.filter((item) => item.patient_id === patient.patient_id).sort((a,b) => new Date(b.recorded_at ?? b.created_at ?? 0).getTime() - new Date(a.recorded_at ?? a.created_at ?? 0).getTime())[0];
              const patientNameValue = person ? `${person.first_name} ${person.last_name}` : patientName(patient.patient_id);
              const patientCode = person?.patient_code ?? '—';
              const patientHref = `/patients/${patient.patient_id}?admission=${patient.id}`;
              return (
                <div key={patient.id ?? index} className={cn('relative p-4 transition-colors hover:bg-muted/30 focus-within:ring-2 focus-within:ring-primary focus-within:ring-inset', statusTone(patient.status))}>
                  <Link to={patientHref} aria-label={`Open current treatment record for ${patientNameValue}`} className="absolute inset-0 z-0 rounded-none focus:outline-none focus:ring-2 focus:ring-primary focus:ring-inset" />
                  <div className="relative z-10 flex flex-wrap items-center justify-between gap-3 pointer-events-none">
                    <div className="flex min-w-0 items-center gap-3">
                      <div className="text-center px-3 py-2 bg-muted rounded-lg shrink-0"><p className="text-xs text-muted-foreground">Bed</p><p className="font-bold text-sm">{patient.bed_number ?? patient.bed ?? '—'}</p></div>
                      <div className="min-w-0">
                        <p className="font-semibold truncate">{patientNameValue}</p>
                        <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
                          <span>ID: {patientCode}</span><span aria-hidden="true">·</span><span>Ward: {patient.ward ?? patient.ward_name ?? 'Ward'}</span><span aria-hidden="true">·</span><span>Bed: {patient.bed_number ?? patient.bed ?? '—'}</span>
                        </div>
                        {latestVital?.recorded_at && <p className="mt-1 text-[11px] text-muted-foreground">Last vitals: {new Date(latestVital.recorded_at).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })}</p>}
                        {patient.status === 'critical' && <span className="badge-critical pulse-critical inline-flex mt-1"><AlertTriangle className="w-3 h-3 mr-1" />Clinical review</span>}
                      </div>
                    </div>
                    <div className="pointer-events-auto flex flex-wrap gap-2">
                      <button type="button" className="btn-secondary text-sm py-1.5" onClick={() => setNoteTarget(patient)}><FileText className="w-4 h-4" /> Notes</button>
                      <Link to={`/vitals?patient=${patient.patient_id}`} className="btn-secondary text-sm py-1.5"><HeartPulse className="w-4 h-4" /> Vitals</Link>
                      <Link to={`/medications?patient=${patient.patient_id}`} className="btn-ghost text-sm py-1.5"><Syringe className="w-4 h-4" /> Meds</Link>
                    </div>
                  </div>
                </div>
              );
            })}
            {!inpatientRows.length && <div className="p-8 text-center text-sm text-muted-foreground">No active inpatients are currently available.</div>}
          </div>
        </section>

        <section className="card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between"><div><h2 className="font-semibold">Medication Schedule</h2><p className="text-xs text-muted-foreground">Live MAR slots</p></div><Link to="/medications" className="text-sm text-primary">Open MAR</Link></div>
          <div className="divide-y divide-border max-h-[28rem] overflow-y-auto">
            {dueMeds.slice(0, 20).map((med, index) => <div key={med.id ?? index} className={cn('p-4', overdueMeds.some(x => x.id === med.id) && 'bg-critical/5')}><div className="flex items-start justify-between gap-2"><button type="button" className="text-left" onClick={() => setMedTarget(med)}><p className="font-medium text-sm">{med.medication_name}</p><p className="text-xs text-muted-foreground">{patientName(med.patient_id)} · {med.dose ?? 'dose not recorded'}</p></button><span className={cn('badge-status', overdueMeds.some(x => x.id === med.id) ? 'badge-critical pulse-critical' : 'badge-warning')}>{med.scheduled_at ? new Date(med.scheduled_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : 'Due'}</span></div></div>)}
            {!dueMeds.length && <div className="p-8 text-center text-sm text-muted-foreground">No medication administrations are currently due.</div>}
          </div>
        </section>
      </div>

      {medTarget && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true" aria-labelledby="due-med-title">
        <div className="w-full max-w-xl rounded-2xl bg-card border border-border shadow-xl">
          <div className="flex items-center justify-between border-b border-border p-5"><div><h2 id="due-med-title" className="font-semibold">Medication due now</h2><p className="text-xs text-muted-foreground">{patientName(medTarget.patient_id)} · current due window only</p></div><button type="button" className="p-2 rounded-lg hover:bg-muted" aria-label="Close medication due view" onClick={() => setMedTarget(null)}><X className="w-4 h-4" /></button></div>
          <div className="p-5 space-y-3">
            {dueMeds.filter((m) => m.patient_id === medTarget.patient_id && m.scheduled_at && new Date(m.scheduled_at).getTime() >= Date.now() - Number(m.due_window_minutes ?? 30) * 60_000 && new Date(m.scheduled_at).getTime() <= Date.now() + 5 * 60_000).map((m) => <div key={m.id} className="rounded-xl border p-4 flex items-center justify-between gap-3"><div><p className="font-medium">{m.medication_name}</p><p className="text-xs text-muted-foreground">{m.dose ?? 'Dose not recorded'} · {m.route ?? 'Route not recorded'}</p></div><Link to="/medications" className="btn-primary text-sm">Open administration</Link></div>)}
            {!dueMeds.some((m) => m.patient_id === medTarget.patient_id && m.scheduled_at && new Date(m.scheduled_at).getTime() >= Date.now() - Number(m.due_window_minutes ?? 30) * 60_000 && new Date(m.scheduled_at).getTime() <= Date.now() + 5 * 60_000) && <p className="text-sm text-muted-foreground">No medication is inside the current due window. Later scheduled doses are intentionally hidden.</p>}
          </div>
        </div>
      </div>}
      {noteTarget && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true" aria-labelledby="nursing-note-title">
        <div className="w-full max-w-2xl rounded-2xl bg-card border border-border shadow-xl">
          <div className="flex items-center justify-between border-b border-border p-5">
            <div><h2 id="nursing-note-title" className="font-semibold">Nursing note</h2><p className="text-xs text-muted-foreground">{patientName(noteTarget.patient_id)} · current admission only</p></div>
            <button type="button" className="p-2 rounded-lg hover:bg-muted" aria-label="Close nursing note" onClick={() => setNoteTarget(null)}><X className="w-4 h-4" /></button>
          </div>
          <div className="space-y-4 p-5">
            <textarea className="input-medical min-h-28 w-full" placeholder="Progress note, observation or intervention performed" value={noteForm.note_text} onChange={(e) => setNoteForm((v) => ({ ...v, note_text: e.target.value }))} />
            <div className="grid gap-4 md:grid-cols-3">
              <textarea className="input-medical min-h-24 w-full" placeholder="Assessment" value={noteForm.assessment} onChange={(e) => setNoteForm((v) => ({ ...v, assessment: e.target.value }))} />
              <textarea className="input-medical min-h-24 w-full" placeholder="Intervention" value={noteForm.intervention} onChange={(e) => setNoteForm((v) => ({ ...v, intervention: e.target.value }))} />
              <textarea className="input-medical min-h-24 w-full" placeholder="Evaluation" value={noteForm.evaluation} onChange={(e) => setNoteForm((v) => ({ ...v, evaluation: e.target.value }))} />
            </div>
            <div className="flex justify-end gap-2"><button type="button" className="btn-secondary" onClick={() => setNoteTarget(null)}>Cancel</button><button type="button" className="btn-primary inline-flex items-center gap-2" disabled={noteSaving || !noteForm.note_text.trim()} onClick={() => void saveNursingNote()}><Save className="w-4 h-4" />{noteSaving ? 'Saving…' : 'Save note'}</button></div>
          </div>
        </div>
      </div>}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <section className="card-medical p-5"><div className="flex justify-between items-start mb-3"><div><h2 className="font-semibold">Handover & continuity</h2><p className="text-sm text-muted-foreground">Unacknowledged handovers remain visible until acknowledged.</p></div><Link to="/nursing-handover" className="text-sm text-primary">Open</Link></div><p className="text-3xl font-bold tabular-nums">{pendingHandovers.length}</p><p className="text-xs text-muted-foreground mt-1">pending acknowledgement</p></section>
        <section className="card-medical p-5"><div className="flex justify-between items-start mb-3"><div><h2 className="font-semibold">Nursing service queue</h2><p className="text-sm text-muted-foreground">Patients awaiting or already claimed by nursing.</p></div><Link to="/department-queue" className="text-sm text-primary">Open queue</Link></div><p className="text-3xl font-bold tabular-nums">{queue.length}</p><p className="text-xs text-muted-foreground mt-1">active queue items</p></section>
      </div>
    </div>
  );
}
