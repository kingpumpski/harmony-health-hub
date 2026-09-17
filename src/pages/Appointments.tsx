import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Calendar, CheckCircle2, Edit3, Play, Plus, UserCheck, Stethoscope, ClipboardCheck, Clock3, Activity } from 'lucide-react';
import { notifyRoles, notify } from '@/lib/notifications';
import { playWorkflowSound } from '@/lib/workflowFeedback';

interface Patient { id: string; first_name: string; last_name: string; user_id: string | null }
interface Appointment { id: string; patient_id: string; scheduled_at: string; reason: string | null; status: string; department: string | null; attending_officer_id?: string | null; treatment_status?: string | null; treatment_notes?: string | null }
const clinicalRoles = new Set(['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse']);
const editableRoles = new Set(['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'front_desk']);
const treatmentStatuses = ['scheduled', 'claimed', 'in_progress', 'completed', 'cancelled', 'no_show'];
const closedStatuses = new Set(['completed', 'cancelled', 'no_show']);

export default function Appointments() {
  const { user } = useAuth(); const navigate = useNavigate();
  const [patients, setPatients] = useState<Patient[]>([]); const [appts, setAppts] = useState<Appointment[]>([]);
  const [pid, setPid] = useState(''); const [when, setWhen] = useState(new Date(Date.now() + 60 * 60 * 1000).toISOString().slice(0, 16));
  const [dept, setDept] = useState('General Outpatient'); const [reason, setReason] = useState(''); const [editing, setEditing] = useState<Appointment | null>(null);
  const [saving, setSaving] = useState(false); const [startingEncounter, setStartingEncounter] = useState<string | null>(null); const [advancing, setAdvancing] = useState<string | null>(null);
  const role = String(user?.role ?? ''); const isStaff = role !== 'patient' && Boolean(user); const canClaim = clinicalRoles.has(role); const canEdit = editableRoles.has(role); const currentUserId = user?.id ?? '';

  const load = async () => {
    const [{ data: pts, error: patientError }, { data: aps, error: appointmentError }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name, user_id').limit(300),
      supabase.from('appointments').select('*').order('scheduled_at', { ascending: true }).limit(200),
    ]);
    if (patientError) toast({ title: 'Unable to load patients', description: patientError.message, variant: 'destructive' });
    if (appointmentError) toast({ title: 'Unable to load appointments', description: appointmentError.message, variant: 'destructive' });
    setPatients(pts ?? []); setAppts(aps ?? []);
  };

  useEffect(() => {
    void load();
    const ch = supabase.channel(`appt-page-${user?.id ?? 'anonymous'}`).on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' }, (payload) => {
      if (payload.eventType === 'INSERT') playWorkflowSound('info');
      if (payload.eventType === 'UPDATE' && String((payload.new as { treatment_status?: string }).treatment_status ?? '').toLowerCase() === 'completed') playWorkflowSound('success');
      void load();
    }).subscribe();
    return () => { void supabase.removeChannel(ch); };
  }, [user?.id]);

  const patientName = useMemo(() => new Map(patients.map((p) => [p.id, `${p.first_name} ${p.last_name}`])), [patients]);
  const todayAppointments = useMemo(() => { const start = new Date(); start.setHours(0, 0, 0, 0); const end = new Date(); end.setHours(23, 59, 59, 999); return appts.filter((a) => { const t = new Date(a.scheduled_at).getTime(); return t >= start.getTime() && t <= end.getTime(); }); }, [appts]);
  const reviewAppointments = useMemo(() => appts.filter((a) => ['checked_in', 'review'].includes(String(a.status).toLowerCase()) || ['checked_in', 'review'].includes(String(a.treatment_status ?? '').toLowerCase())), [appts]);
  const activeToday = todayAppointments.filter((a) => !closedStatuses.has(a.treatment_status || a.status || 'scheduled'));
  const inProgressToday = todayAppointments.filter((a) => ['claimed', 'in_progress'].includes(a.treatment_status || a.status));
  const completedToday = todayAppointments.filter((a) => (a.treatment_status || a.status) === 'completed');

  const create = async (e: React.FormEvent) => {
    e.preventDefault(); if (!pid) return toast({ title: 'Select a patient', description: 'Choose the patient for this appointment.', variant: 'destructive' });
    const { data, error } = await supabase.rpc('create_appointment_workflow' as never, { _patient_id: pid, _scheduled_at: new Date(when).toISOString(), _department: dept, _reason: reason || null } as never);
    if (error) return toast({ title: 'Failed to schedule appointment', description: error.message, variant: 'destructive' });
    const created = data as unknown as Appointment; playWorkflowSound('success'); toast({ title: 'Appointment scheduled' }); const p = patients.find((x) => x.id === pid); const name = p ? `${p.first_name} ${p.last_name}` : 'patient';
    await notifyRoles(['practitioner', 'nurse', 'midwife', 'specialist_nurse', 'front_desk'], { title: 'New appointment', message: `${name} scheduled for ${dept} on ${new Date(when).toLocaleString()}`, severity: 'info', category: 'appointment', link: '/appointments', relatedPatientId: pid, relatedEntityId: created?.id });
    if (p?.user_id && created?.id) await notify({ recipientUserId: p.user_id, title: 'Your appointment is booked', message: `${dept} on ${new Date(when).toLocaleString()}`, severity: 'success', category: 'appointment', link: '/patient-portal', relatedPatientId: pid, relatedEntityId: created.id });
    setReason(''); setPid(''); await load();
  };

  const claim = async (appointmentId: string) => { if (!canClaim) return; const { error } = await supabase.rpc('claim_appointment' as never, { _appointment_id: appointmentId } as never); if (error) return toast({ title: 'Could not claim appointment', description: error.message, variant: 'destructive' }); playWorkflowSound('success'); toast({ title: 'Appointment assigned to you', description: 'You can now start treatment and update the care status.' }); await load(); };

  const advanceTreatment = async (appointment: Appointment, treatmentStatus: string) => {
    if (!canEdit) return; setAdvancing(appointment.id);
    const { error } = await supabase.rpc('update_appointment_workflow' as never, { _appointment_id: appointment.id, _scheduled_at: appointment.scheduled_at, _department: appointment.department || 'General Outpatient', _reason: appointment.reason || '', _treatment_status: treatmentStatus, _treatment_notes: appointment.treatment_notes || '' } as never);
    setAdvancing(null);
    if (error) return toast({ title: 'Could not update treatment', description: error.message, variant: 'destructive' });
    playWorkflowSound(treatmentStatus === 'completed' ? 'success' : 'info'); toast({ title: treatmentStatus === 'completed' ? 'Appointment completed' : 'Treatment started', description: treatmentStatus === 'completed' ? 'The patient has been removed from the active treatment counter.' : 'The appointment is now in treatment.' }); await load();
  };

  const startEncounter = async (appointment: Appointment) => { if (!canClaim) return; setStartingEncounter(appointment.id); const { data, error } = await supabase.rpc('start_appointment_encounter' as never, { _appointment_id: appointment.id, _symptoms: null, _clerking_notes: null } as never); setStartingEncounter(null); if (error) return toast({ title: 'Could not start encounter', description: error.message, variant: 'destructive' }); playWorkflowSound('success'); toast({ title: 'Clinical encounter started', description: 'The appointment is now in treatment.' }); await load(); const encounterId = typeof data === 'string' ? data : String(data ?? ''); navigate(`/encounters?patient=${encodeURIComponent(appointment.patient_id)}${encounterId ? `&encounter=${encodeURIComponent(encounterId)}` : ''}`); };

  const saveEdit = async (event: React.FormEvent<HTMLFormElement>) => { event.preventDefault(); if (!editing || !canEdit) return; setSaving(true); const form = new FormData(event.currentTarget); const { error } = await supabase.rpc('update_appointment_workflow' as never, { _appointment_id: editing.id, _scheduled_at: new Date(String(form.get('scheduled_at'))).toISOString(), _department: String(form.get('department') ?? ''), _reason: String(form.get('reason') ?? ''), _treatment_status: String(form.get('treatment_status') ?? 'scheduled'), _treatment_notes: String(form.get('treatment_notes') ?? '') } as never); setSaving(false); if (error) return toast({ title: 'Could not save appointment', description: error.message, variant: 'destructive' }); setEditing(null); playWorkflowSound('success'); toast({ title: 'Appointment updated' }); await load(); };

  const renderAppointment = (a: Appointment) => { const assignedToMe = a.attending_officer_id === currentUserId; const treatmentStatus = a.treatment_status || a.status || 'scheduled'; return <div key={a.id} className="rounded-xl border border-border p-4 space-y-3"><div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between"><button type="button" onClick={() => navigate(`/patients/${a.patient_id}`)} className="text-left hover:text-primary min-w-0"><p className="font-medium text-sm">{patientName.get(a.patient_id) || 'Unknown patient'}</p><p className="text-xs text-muted-foreground">{new Date(a.scheduled_at).toLocaleString()} · {a.department || 'General'}</p>{a.reason && <p className="text-xs text-muted-foreground mt-0.5">{a.reason}</p>}</button><span className="text-xs px-2 py-1 rounded-full bg-muted text-muted-foreground capitalize shrink-0">{treatmentStatus.replaceAll('_', ' ')}</span></div><div className="flex flex-wrap gap-2">
    {canClaim && !a.attending_officer_id && !closedStatuses.has(treatmentStatus) && <button type="button" onClick={() => void claim(a.id)} className="btn-primary inline-flex items-center gap-1.5 text-xs"><UserCheck className="w-3.5 h-3.5" /> Attend to patient</button>}
    {canClaim && assignedToMe && treatmentStatus === 'claimed' && <button type="button" disabled={advancing === a.id} onClick={() => void advanceTreatment(a, 'in_progress')} className="btn-primary inline-flex items-center gap-1.5 text-xs"><Play className="w-3.5 h-3.5" />{advancing === a.id ? 'Starting…' : 'Start treatment'}</button>}
    {canClaim && assignedToMe && ['claimed', 'in_progress'].includes(treatmentStatus) && <button type="button" disabled={startingEncounter === a.id} onClick={() => void startEncounter(a)} className="btn-secondary inline-flex items-center gap-1.5 text-xs"><Stethoscope className="w-3.5 h-3.5" />{startingEncounter === a.id ? 'Starting…' : 'Start encounter'}</button>}
    {canClaim && assignedToMe && treatmentStatus === 'in_progress' && <button type="button" disabled={advancing === a.id} onClick={() => void advanceTreatment(a, 'completed')} className="btn-secondary inline-flex items-center gap-1.5 text-xs"><CheckCircle2 className="w-3.5 h-3.5" /> Complete</button>}
    {canEdit && (assignedToMe || role === 'admin' || role === 'front_desk') && <button type="button" onClick={() => setEditing(a)} className="btn-secondary inline-flex items-center gap-1.5 text-xs"><Edit3 className="w-3.5 h-3.5" /> Edit</button>}
    <button type="button" onClick={() => navigate(`/patients/${a.patient_id}`)} className="btn-secondary inline-flex items-center gap-1.5 text-xs"><CheckCircle2 className="w-3.5 h-3.5" /> Open patient</button>
  </div>{a.attending_officer_id && <p className="text-xs text-muted-foreground">Attending officer: {assignedToMe ? 'You' : 'Assigned officer'}</p>}</div>; };

  return <div className="space-y-6 animate-fade-in">
    <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Calendar className="w-6 h-6 text-primary" /> Appointments</h1><p className="text-muted-foreground">Live appointment worklist with treatment-stage counters, review attention and direct clinical actions.</p></div>
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3" aria-label="Appointment workflow counters">
      {[['Today active', activeToday.length, 'text-primary', 'bg-primary/5'], ['Needs review', reviewAppointments.length, 'text-warning', 'bg-warning/5'], ['In treatment', inProgressToday.length, 'text-info', 'bg-info/5'], ['Completed today', completedToday.length, 'text-success', 'bg-success/5']].map(([label, value, tone, surface]) => <div key={String(label)} className={`card-medical ${surface} p-4 transition-all duration-300 hover:-translate-y-1 ${Number(value) > 0 && label !== 'Completed today' ? 'animate-pulse' : ''}`}><div className="flex items-center justify-between"><p className="text-xs text-muted-foreground">{label}</p><Activity className={`w-4 h-4 ${tone}`} /></div><p className={`text-2xl font-bold mt-1 ${tone}`}>{value}</p></div>)}
    </div>
    {reviewAppointments.length > 0 && <section className="card-medical p-5 border-warning/30"><div className="flex items-center justify-between mb-3"><div><h2 className="font-semibold flex items-center gap-2"><ClipboardCheck className="w-4 h-4 text-warning" /> New reviews / checked-in patients</h2><p className="text-xs text-muted-foreground">Patients requiring clinician attention before the next treatment step.</p></div><span className="text-xs rounded-full bg-warning/10 text-warning px-2 py-1">{reviewAppointments.length} waiting</span></div><div className="space-y-2">{reviewAppointments.slice(0, 8).map((a) => <button key={a.id} type="button" onClick={() => navigate(`/patients/${a.patient_id}`)} className="w-full text-left rounded-lg border border-border p-3 hover:bg-muted/50"><div className="flex items-center justify-between gap-3"><span className="font-medium text-sm">{patientName.get(a.patient_id) || 'Unknown patient'}</span><span className="text-xs text-warning">{new Date(a.scheduled_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span></div><p className="text-xs text-muted-foreground">{a.department || 'General'} · {a.reason || 'Clinical review'}</p></button>)}</div></section>}
    <div className="grid gap-6 lg:grid-cols-[360px_1fr]">
      {isStaff && <form onSubmit={create} className="card-medical p-5 space-y-3 h-fit"><h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New Appointment</h2><select required value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}</select><input required type="datetime-local" value={when} onChange={(e) => setWhen(e.target.value)} className="input-medical w-full" /><select value={dept} onChange={(e) => setDept(e.target.value)} className="input-medical w-full"><option>General Outpatient</option><option>Specialist Consultation</option><option>Maternity</option><option>Fertility</option><option>Telemedicine</option></select><input value={reason} onChange={(e) => setReason(e.target.value)} className="input-medical w-full" placeholder="Reason (optional)" /><button type="submit" className="btn-primary w-full">Schedule</button></form>}
      <div className="card-medical p-5"><div className="flex items-center justify-between mb-3"><div><h2 className="font-semibold">Today's active appointment list</h2><p className="text-xs text-muted-foreground">Counter decreases when treatment is completed or the appointment is closed.</p></div><span className="text-xs text-muted-foreground flex items-center gap-1"><Clock3 className="w-3.5 h-3.5" />{activeToday.length} active</span></div><div className="space-y-3">{todayAppointments.map(renderAppointment)}{todayAppointments.length === 0 && <p className="text-sm text-muted-foreground text-center py-6">No appointments scheduled for today.</p>}</div></div>
    </div>
    <div className="card-medical p-5"><div className="flex items-center justify-between mb-3"><h2 className="font-semibold">Upcoming & recent</h2><span className="text-xs text-muted-foreground">{appts.length} records</span></div><div className="space-y-3">{appts.filter((a) => !todayAppointments.some((t) => t.id === a.id)).map(renderAppointment)}{appts.length === todayAppointments.length && <p className="text-sm text-muted-foreground text-center py-6">No other appointments.</p>}</div></div>
    {editing && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true"><form onSubmit={saveEdit} className="w-full max-w-xl rounded-2xl bg-card border border-border shadow-xl p-6 space-y-4 max-h-[90vh] overflow-y-auto"><div className="flex items-center justify-between"><div><h2 className="text-lg font-semibold">Edit appointment</h2><p className="text-sm text-muted-foreground">{patientName.get(editing.patient_id) || 'Patient'}</p></div><button type="button" onClick={() => setEditing(null)} className="btn-secondary">Close</button></div><label className="block space-y-1 text-sm"><span>Scheduled time</span><input name="scheduled_at" required type="datetime-local" defaultValue={new Date(editing.scheduled_at).toISOString().slice(0, 16)} className="input-medical w-full" /></label><label className="block space-y-1 text-sm"><span>Department</span><select name="department" defaultValue={editing.department || 'General Outpatient'} className="input-medical w-full"><option>General Outpatient</option><option>Specialist Consultation</option><option>Maternity</option><option>Fertility</option><option>Telemedicine</option></select></label><label className="block space-y-1 text-sm"><span>Reason</span><input name="reason" defaultValue={editing.reason || ''} className="input-medical w-full" /></label><label className="block space-y-1 text-sm"><span>Treatment status</span><select name="treatment_status" defaultValue={editing.treatment_status || 'scheduled'} className="input-medical w-full">{treatmentStatuses.map((status) => <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>)}</select></label><label className="block space-y-1 text-sm"><span>Treatment notes</span><textarea name="treatment_notes" defaultValue={editing.treatment_notes || ''} className="input-medical min-h-28 w-full" placeholder="Clinical workflow notes…" /></label><div className="flex justify-end gap-2"><button type="button" onClick={() => setEditing(null)} className="btn-secondary">Cancel</button><button disabled={saving} type="submit" className="btn-primary">{saving ? 'Saving…' : 'Save changes'}</button></div></form></div>}
  </div>;
}
