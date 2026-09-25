import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Calendar, CheckCircle2, Edit3, Play, Plus, UserCheck, Stethoscope, ClipboardCheck, Clock3, Activity, RefreshCw, Search, X } from 'lucide-react';
import { notifyRoles } from '@/lib/notifications';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { searchPatientDirectory } from '@/lib/patientDirectory';

interface Patient { id: string; first_name: string; last_name: string; user_id?: string | null }
interface Appointment { id: string; patient_id: string; scheduled_at: string; reason: string | null; status: string; department: string | null; attending_officer_id?: string | null; treatment_status?: string | null; treatment_notes?: string | null }

const clinicalRoles = new Set(['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse']);
const editableRoles = new Set(['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'front_desk']);
const treatmentStatuses = ['scheduled', 'claimed', 'in_progress', 'completed', 'cancelled', 'no_show'];
const closedStatuses = new Set(['completed', 'cancelled', 'no_show']);

type ListFilter = 'today' | 'upcoming' | 'all';

export default function Appointments() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [appts, setAppts] = useState<Appointment[]>([]);
  const [pid, setPid] = useState('');
  const [when, setWhen] = useState(new Date(Date.now() + 60 * 60 * 1000).toISOString().slice(0, 16));
  const [dept, setDept] = useState('General Outpatient');
  const [reason, setReason] = useState('');
  const [editing, setEditing] = useState<Appointment | null>(null);
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(true);
  const [startingEncounter, setStartingEncounter] = useState<string | null>(null);
  const [advancing, setAdvancing] = useState<string | null>(null);
  const [listFilter, setListFilter] = useState<ListFilter>('today');
  const [statusFilter, setStatusFilter] = useState('all');
  const [search, setSearch] = useState('');
  const [showScheduler, setShowScheduler] = useState(false);

  const role = String(user?.role ?? '');
  const isStaff = role !== 'patient' && Boolean(user);
  const canClaim = clinicalRoles.has(role);
  const canEdit = editableRoles.has(role);
  const currentUserId = user?.id ?? '';

  const load = async (silent = false) => {
    if (!silent) setLoading(true);
    const [{ data: pts, error: patientError }, { data: aps, error: appointmentError }] = await Promise.all([
      searchPatientDirectory('', 300),
      (async () => { const { data, error } = await getOperationalWorkspace('appointments', 200); return { data: (data as any)?.appointments ?? [], error }; })(),
    ]);
    if (patientError) toast({ title: 'Unable to load patients', description: patientError.message, variant: 'destructive' });
    if (appointmentError) toast({ title: 'Unable to load appointments', description: appointmentError.message, variant: 'destructive' });
    setPatients(pts ?? []);
    setAppts(aps ?? []);
    setLoading(false);
  };

  useEffect(() => {
    void load();
    const ch = supabase.channel(`appt-page-${user?.id ?? 'anonymous'}`).on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' }, (payload) => {
      if (payload.eventType === 'INSERT') playWorkflowSound('info');
      if (payload.eventType === 'UPDATE' && String((payload.new as { treatment_status?: string }).treatment_status ?? '').toLowerCase() === 'completed') playWorkflowSound('success');
      void load(true);
    }).subscribe();
    return () => { void supabase.removeChannel(ch); };
  }, [user?.id]);

  const patientName = useMemo(() => new Map(patients.map((p) => [p.id, `${p.first_name} ${p.last_name}`])), [patients]);
  const todayAppointments = useMemo(() => {
    const start = new Date(); start.setHours(0, 0, 0, 0);
    const end = new Date(); end.setHours(23, 59, 59, 999);
    return appts.filter((a) => { const t = new Date(a.scheduled_at).getTime(); return t >= start.getTime() && t <= end.getTime(); });
  }, [appts]);
  const reviewAppointments = useMemo(() => appts.filter((a) => ['checked_in', 'review'].includes(String(a.status).toLowerCase()) || ['checked_in', 'review'].includes(String(a.treatment_status ?? '').toLowerCase())), [appts]);
  const activeToday = todayAppointments.filter((a) => !closedStatuses.has(a.treatment_status || a.status || 'scheduled'));
  const inProgressToday = todayAppointments.filter((a) => ['claimed', 'in_progress'].includes(a.treatment_status || a.status));
  const completedToday = todayAppointments.filter((a) => (a.treatment_status || a.status) === 'completed');

  const visibleAppointments = useMemo(() => {
    const now = Date.now();
    const query = search.trim().toLowerCase();
    return appts
      .filter((a) => {
        const time = new Date(a.scheduled_at).getTime();
        if (listFilter === 'today' && !todayAppointments.some((t) => t.id === a.id)) return false;
        if (listFilter === 'upcoming' && time < now) return false;
        if (statusFilter !== 'all' && (a.treatment_status || a.status || 'scheduled') !== statusFilter) return false;
        if (query) {
          const name = patientName.get(a.patient_id) ?? '';
          return name.toLowerCase().includes(query) || (a.department ?? '').toLowerCase().includes(query) || (a.reason ?? '').toLowerCase().includes(query);
        }
        return true;
      })
      .sort((a, b) => new Date(a.scheduled_at).getTime() - new Date(b.scheduled_at).getTime());
  }, [appts, listFilter, patientName, search, statusFilter, todayAppointments]);

  const create = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return toast({ title: 'Select a patient', description: 'Choose the patient for this appointment.', variant: 'destructive' });
    setSaving(true);
    const { data, error } = await supabase.rpc('create_appointment_workflow' as never, { _patient_id: pid, _scheduled_at: new Date(when).toISOString(), _department: dept, _reason: reason || null } as never);
    setSaving(false);
    if (error) return toast({ title: 'Failed to schedule appointment', description: error.message, variant: 'destructive' });
    const created = data as unknown as Appointment;
    playWorkflowSound('success');
    toast({ title: 'Appointment scheduled' });
    const p = patients.find((x) => x.id === pid);
    const name = p ? `${p.first_name} ${p.last_name}` : 'patient';
    await notifyRoles(['practitioner', 'nurse', 'midwife', 'specialist_nurse', 'front_desk'], { title: 'New appointment', message: `${name} scheduled for ${dept} on ${new Date(when).toLocaleString()}`, severity: 'info', category: 'appointment', link: '/appointments', relatedPatientId: pid, relatedEntityId: created?.id });
    setReason(''); setPid(''); setShowScheduler(false); await load();
  };

  const claim = async (appointmentId: string) => {
    if (!canClaim) return;
    const { error } = await supabase.rpc('claim_appointment' as never, { _appointment_id: appointmentId } as never);
    if (error) return toast({ title: 'Could not claim appointment', description: error.message, variant: 'destructive' });
    playWorkflowSound('success'); toast({ title: 'Appointment assigned to you', description: 'You can now start treatment and update the care status.' }); await load(true);
  };

  const advanceTreatment = async (appointment: Appointment, treatmentStatus: string) => {
    if (!canEdit) return;
    setAdvancing(appointment.id);
    const { error } = await supabase.rpc('update_appointment_workflow' as never, { _appointment_id: appointment.id, _scheduled_at: appointment.scheduled_at, _department: appointment.department || 'General Outpatient', _reason: appointment.reason || '', _treatment_status: treatmentStatus, _treatment_notes: appointment.treatment_notes || '' } as never);
    setAdvancing(null);
    if (error) return toast({ title: 'Could not update treatment', description: error.message, variant: 'destructive' });
    playWorkflowSound(treatmentStatus === 'completed' ? 'success' : 'info');
    toast({ title: treatmentStatus === 'completed' ? 'Appointment completed' : 'Treatment started', description: treatmentStatus === 'completed' ? 'The patient has been removed from the active treatment counter.' : 'The appointment is now in treatment.' });
    await load(true);
  };

  const startEncounter = async (appointment: Appointment) => {
    if (!canClaim) return;
    setStartingEncounter(appointment.id);
    const { data, error } = await supabase.rpc('start_appointment_encounter' as never, { _appointment_id: appointment.id, _symptoms: null, _clerking_notes: null } as never);
    setStartingEncounter(null);
    if (error) return toast({ title: 'Could not start encounter', description: error.message, variant: 'destructive' });
    playWorkflowSound('success'); toast({ title: 'Clinical encounter started', description: 'The appointment is now in treatment.' });
    await load(true);
    const encounterId = typeof data === 'string' ? data : String(data ?? '');
    navigate(`/encounters?patient=${encodeURIComponent(appointment.patient_id)}${encounterId ? `&encounter=${encodeURIComponent(encounterId)}` : ''}`);
  };

  const saveEdit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!editing || !canEdit) return;
    setSaving(true);
    const form = new FormData(event.currentTarget);
    const { error } = await supabase.rpc('update_appointment_workflow' as never, { _appointment_id: editing.id, _scheduled_at: new Date(String(form.get('scheduled_at'))).toISOString(), _department: String(form.get('department') ?? ''), _reason: String(form.get('reason') ?? ''), _treatment_status: String(form.get('treatment_status') ?? 'scheduled'), _treatment_notes: String(form.get('treatment_notes') ?? '') } as never);
    setSaving(false);
    if (error) return toast({ title: 'Could not save appointment', description: error.message, variant: 'destructive' });
    setEditing(null); playWorkflowSound('success'); toast({ title: 'Appointment updated' }); await load(true);
  };

  const renderAppointment = (a: Appointment) => {
    const assignedToMe = a.attending_officer_id === currentUserId;
    const treatmentStatus = a.treatment_status || a.status || 'scheduled';
    return <article key={a.id} className="rounded-xl border border-border bg-card p-4 space-y-3 transition-colors hover:bg-muted/20">
      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
        <button type="button" onClick={() => navigate(`/patients/${a.patient_id}`)} className="text-left hover:text-primary min-w-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-md">
          <p className="font-medium text-sm">{patientName.get(a.patient_id) || 'Unknown patient'}</p>
          <p className="text-xs text-muted-foreground">{new Date(a.scheduled_at).toLocaleString()} · {a.department || 'General'}</p>
          {a.reason && <p className="text-xs text-muted-foreground mt-0.5">{a.reason}</p>}
        </button>
        <span className="text-xs px-2.5 py-1 rounded-full bg-muted text-muted-foreground capitalize shrink-0 self-start">{treatmentStatus.replaceAll('_', ' ')}</span>
      </div>
      <div className="flex flex-wrap gap-2">
        {canClaim && !a.attending_officer_id && !closedStatuses.has(treatmentStatus) && <button type="button" onClick={() => void claim(a.id)} className="btn-primary inline-flex items-center gap-1.5 text-xs"><UserCheck className="w-3.5 h-3.5" /> Attend to patient</button>}
        {canClaim && assignedToMe && treatmentStatus === 'claimed' && <button type="button" disabled={advancing === a.id} onClick={() => void advanceTreatment(a, 'in_progress')} className="btn-primary inline-flex items-center gap-1.5 text-xs"><Play className="w-3.5 h-3.5" />{advancing === a.id ? 'Starting…' : 'Start treatment'}</button>}
        {canClaim && assignedToMe && ['claimed', 'in_progress'].includes(treatmentStatus) && <button type="button" disabled={startingEncounter === a.id} onClick={() => void startEncounter(a)} className="btn-secondary inline-flex items-center gap-1.5 text-xs"><Stethoscope className="w-3.5 h-3.5" />{startingEncounter === a.id ? 'Starting…' : 'Start encounter'}</button>}
        {canClaim && assignedToMe && treatmentStatus === 'in_progress' && <button type="button" disabled={advancing === a.id} onClick={() => void advanceTreatment(a, 'completed')} className="btn-secondary inline-flex items-center gap-1.5 text-xs"><CheckCircle2 className="w-3.5 h-3.5" /> Complete</button>}
        {canEdit && (assignedToMe || role === 'admin' || role === 'front_desk') && <button type="button" onClick={() => setEditing(a)} className="btn-secondary inline-flex items-center gap-1.5 text-xs"><Edit3 className="w-3.5 h-3.5" /> Edit</button>}
        <button type="button" onClick={() => navigate(`/patients/${a.patient_id}`)} className="btn-secondary inline-flex items-center gap-1.5 text-xs"><CheckCircle2 className="w-3.5 h-3.5" /> Open patient</button>
      </div>
      {a.attending_officer_id && <p className="text-xs text-muted-foreground">Attending officer: {assignedToMe ? 'You' : 'Assigned officer'}</p>}
    </article>;
  };

  return <div className="space-y-6 animate-fade-in">
    <header className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
      <div>
        <div className="flex items-center gap-2"><Calendar className="w-6 h-6 text-primary" /><span className="text-xs font-medium uppercase tracking-wide text-primary">Care coordination</span></div>
        <h1 className="text-2xl font-heading font-bold mt-1">Appointments</h1>
        <p className="text-muted-foreground max-w-2xl">Schedule, review and progress appointments from one focused worklist. Clinical actions remain governed by the existing server-side workflow.</p>
      </div>
      <div className="flex flex-wrap gap-2">
        <button type="button" onClick={() => void load()} disabled={loading} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} /> Refresh</button>
        {isStaff && <button type="button" onClick={() => setShowScheduler((value) => !value)} className="btn-primary inline-flex items-center gap-2"><Plus className="w-4 h-4" /> {showScheduler ? 'Close scheduler' : 'New appointment'}</button>}
      </div>
    </header>

    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3" aria-label="Appointment workflow counters">
      {[['Today active', activeToday.length, 'text-primary', 'bg-primary/5'], ['Needs review', reviewAppointments.length, 'text-warning', 'bg-warning/5'], ['In treatment', inProgressToday.length, 'text-info', 'bg-info/5'], ['Completed today', completedToday.length, 'text-success', 'bg-success/5']].map(([label, value, tone, surface]) => <div key={String(label)} className={`card-medical ${surface} p-4`}><div className="flex items-center justify-between"><p className="text-xs text-muted-foreground">{label}</p><Activity className={`w-4 h-4 ${tone}`} /></div><p className={`text-2xl font-bold mt-1 ${tone}`}>{value}</p></div>)}
    </div>

    {reviewAppointments.length > 0 && <section className="card-medical p-5 border-warning/30" aria-labelledby="review-queue-heading">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between mb-3"><div><h2 id="review-queue-heading" className="font-semibold flex items-center gap-2"><ClipboardCheck className="w-4 h-4 text-warning" /> New reviews / checked-in patients</h2><p className="text-xs text-muted-foreground">Patients requiring clinician attention before the next treatment step.</p></div><span className="text-xs rounded-full bg-warning/10 text-warning px-2 py-1">{reviewAppointments.length} waiting</span></div>
      <div className="grid gap-2 md:grid-cols-2">{reviewAppointments.slice(0, 8).map((a) => <button key={a.id} type="button" onClick={() => navigate(`/patients/${a.patient_id}`)} className="w-full text-left rounded-lg border border-border p-3 hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"><div className="flex items-center justify-between gap-3"><span className="font-medium text-sm truncate">{patientName.get(a.patient_id) || 'Unknown patient'}</span><span className="text-xs text-warning shrink-0">{new Date(a.scheduled_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span></div><p className="text-xs text-muted-foreground truncate">{a.department || 'General'} · {a.reason || 'Clinical review'}</p></button>)}</div>
    </section>}

    {showScheduler && isStaff && <form onSubmit={create} className="card-medical p-5 space-y-4" aria-labelledby="new-appointment-heading">
      <div><h2 id="new-appointment-heading" className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New appointment</h2><p className="text-xs text-muted-foreground mt-1">Create the booking first; clinical treatment status remains controlled by the workflow.</p></div>
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <label className="block space-y-1.5 text-sm"><span>Patient</span><select required value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}</select></label>
        <label className="block space-y-1.5 text-sm"><span>Date & time</span><input required type="datetime-local" value={when} onChange={(e) => setWhen(e.target.value)} className="input-medical w-full" /></label>
        <label className="block space-y-1.5 text-sm"><span>Department</span><select value={dept} onChange={(e) => setDept(e.target.value)} className="input-medical w-full"><option>General Outpatient</option><option>Specialist Consultation</option><option>Maternity</option><option>Fertility</option><option>Telemedicine</option></select></label>
        <label className="block space-y-1.5 text-sm"><span>Reason <span className="text-muted-foreground">(optional)</span></span><input value={reason} onChange={(e) => setReason(e.target.value)} className="input-medical w-full" placeholder="e.g. follow-up review" /></label>
      </div>
      <div className="flex justify-end gap-2"><button type="button" onClick={() => setShowScheduler(false)} className="btn-secondary">Cancel</button><button disabled={saving} type="submit" className="btn-primary">{saving ? 'Scheduling…' : 'Schedule appointment'}</button></div>
    </form>}

    <section className="card-medical p-5" aria-labelledby="appointment-list-heading">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div><h2 id="appointment-list-heading" className="font-semibold">Appointment worklist</h2><p className="text-xs text-muted-foreground">Use the view and filters to move between today’s care, upcoming bookings and the full record.</p></div>
        <div className="flex flex-col sm:flex-row gap-2">
          <label className="relative"><span className="sr-only">Search appointments</span><Search className="absolute left-3 top-2.5 w-4 h-4 text-muted-foreground" /><input value={search} onChange={(e) => setSearch(e.target.value)} className="input-medical pl-9 pr-9 w-full sm:w-64" placeholder="Patient, department or reason" aria-label="Search appointments" />{search && <button type="button" onClick={() => setSearch('')} className="absolute right-2 top-1.5 p-1 rounded hover:bg-muted" aria-label="Clear appointment search"><X className="w-4 h-4" /></button>}</label>
          <label className="sr-only" htmlFor="appointment-status-filter">Appointment status</label><select id="appointment-status-filter" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className="input-medical"><option value="all">All statuses</option>{treatmentStatuses.map((status) => <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>)}</select>
        </div>
      </div>
      <div className="mt-4 flex gap-1 overflow-x-auto border-b border-border" role="tablist" aria-label="Appointment views">
        {([['today', 'Today'], ['upcoming', 'Upcoming'], ['all', 'All appointments']] as const).map(([value, label]) => <button key={value} type="button" role="tab" aria-selected={listFilter === value} onClick={() => setListFilter(value)} className={`shrink-0 px-3 py-2 text-sm border-b-2 ${listFilter === value ? 'border-primary text-primary font-medium' : 'border-transparent text-muted-foreground hover:text-foreground'}`}>{label}</button>)}
      </div>
      <div className="mt-4 flex items-center justify-between gap-3"><span className="text-xs text-muted-foreground">{visibleAppointments.length} shown</span><span className="text-xs text-muted-foreground flex items-center gap-1"><Clock3 className="w-3.5 h-3.5" /> Live updates enabled</span></div>
      <div className="mt-3 space-y-3">
        {loading ? <div className="space-y-3" aria-live="polite"><div className="h-28 rounded-xl bg-muted animate-pulse" /><div className="h-28 rounded-xl bg-muted animate-pulse" /></div> : visibleAppointments.map(renderAppointment)}
        {!loading && visibleAppointments.length === 0 && <div className="py-12 text-center border border-dashed border-border rounded-xl"><Calendar className="w-8 h-8 mx-auto text-muted-foreground mb-2" /><p className="font-medium">No appointments match this view</p><p className="text-sm text-muted-foreground mt-1">{search || statusFilter !== 'all' ? 'Try clearing a filter or search term.' : 'Scheduled appointments will appear here.'}</p></div>}
      </div>
    </section>

    {editing && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true" aria-labelledby="edit-appointment-heading">
      <form onSubmit={saveEdit} className="w-full max-w-xl rounded-2xl bg-card border border-border shadow-xl p-6 space-y-4 max-h-[90vh] overflow-y-auto">
        <div className="flex items-start justify-between gap-4"><div><h2 id="edit-appointment-heading" className="text-lg font-semibold">Edit appointment</h2><p className="text-sm text-muted-foreground">{patientName.get(editing.patient_id) || 'Patient'}</p></div><button type="button" onClick={() => setEditing(null)} className="btn-secondary">Close</button></div>
        <label className="block space-y-1 text-sm"><span>Scheduled time</span><input name="scheduled_at" required type="datetime-local" defaultValue={new Date(editing.scheduled_at).toISOString().slice(0, 16)} className="input-medical w-full" /></label>
        <label className="block space-y-1 text-sm"><span>Department</span><select name="department" defaultValue={editing.department || 'General Outpatient'} className="input-medical w-full"><option>General Outpatient</option><option>Specialist Consultation</option><option>Maternity</option><option>Fertility</option><option>Telemedicine</option></select></label>
        <label className="block space-y-1 text-sm"><span>Reason</span><input name="reason" defaultValue={editing.reason || ''} className="input-medical w-full" /></label>
        <label className="block space-y-1 text-sm"><span>Treatment status</span><select name="treatment_status" defaultValue={editing.treatment_status || 'scheduled'} className="input-medical w-full">{treatmentStatuses.map((status) => <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>)}</select></label>
        <label className="block space-y-1 text-sm"><span>Treatment notes</span><textarea name="treatment_notes" defaultValue={editing.treatment_notes || ''} className="input-medical min-h-28 w-full" placeholder="Clinical workflow notes…" /></label>
        <div className="flex justify-end gap-2"><button type="button" onClick={() => setEditing(null)} className="btn-secondary">Cancel</button><button disabled={saving} type="submit" className="btn-primary">{saving ? 'Saving…' : 'Save changes'}</button></div>
      </form>
    </div>}
  </div>;
}
