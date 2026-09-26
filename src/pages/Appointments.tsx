import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Calendar, CheckCircle2, Clock3, Plus, RefreshCw, Stethoscope, UserCheck, X } from 'lucide-react';
import { notifyRoles } from '@/lib/notifications';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { searchPatientDirectory } from '@/lib/patientDirectory';

interface Patient {
  id: string;
  patient_code: string;
  first_name: string;
  last_name: string;
}
interface Appointment {
  id: string;
  patient_id: string;
  scheduled_at: string;
  reason: string | null;
  status: string;
  department: string | null;
  practitioner_id?: string | null;
  attending_officer_id?: string | null;
  treatment_status?: string | null;
  treatment_notes?: string | null;
  consultation_type?: string | null;
}
interface Clinician {
  id: string;
  first_name: string | null;
  last_name: string | null;
  department: string | null;
  specialization: string | null;
  clinician_role: string;
}

const consultationTypes = [
  'General Consultation',
  'Specialist Consultation',
  'Follow-up Consultation',
  'Fertility Consultation',
  'Maternity Consultation',
  'Telemedicine Consultation',
] as const;

const activeStatuses = new Set(['scheduled', 'claimed', 'in_progress']);

export default function Appointments() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [clinicians, setClinicians] = useState<Clinician[]>([]);
  const [appts, setAppts] = useState<Appointment[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showScheduler, setShowScheduler] = useState(false);
  const [selected, setSelected] = useState<Appointment | null>(null);
  const [startingEncounter, setStartingEncounter] = useState(false);
  const [claiming, setClaiming] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [pid, setPid] = useState('');
  const [consultationType, setConsultationType] = useState<(typeof consultationTypes)[number]>('General Consultation');
  const [clinicianId, setClinicianId] = useState('');
  const [when, setWhen] = useState(new Date(Date.now() + 60 * 60 * 1000).toISOString().slice(0, 16));
  const [reason, setReason] = useState('');

  const role = String(user?.role ?? '');
  const isStaff = Boolean(user) && role !== 'patient';
  const canClaim = ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse'].includes(role);
  const canSchedule = ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'front_desk'].includes(role);
  const currentUserId = user?.id ?? '';

  const load = async (silent = false) => {
    if (!silent) setLoading(true);
    const [{ data: pts, error: patientError }, { data: workspace, error: appointmentError }, { data: staff, error: clinicianError }] = await Promise.all([
      searchPatientDirectory('', 300),
      getOperationalWorkspace('appointments', 300),
      supabase.rpc('get_appointment_clinicians' as never),
    ]);
    if (patientError) toast({ title: 'Unable to load patients', description: patientError.message, variant: 'destructive' });
    if (appointmentError) toast({ title: 'Unable to load appointments', description: appointmentError.message, variant: 'destructive' });
    if (clinicianError) toast({ title: 'Unable to load clinicians', description: clinicianError.message, variant: 'destructive' });
    setPatients((pts ?? []) as Patient[]);
    setClinicians((staff ?? []) as Clinician[]);
    setAppts(((workspace as any)?.appointments ?? []) as Appointment[]);
    setLoading(false);
  };

  useEffect(() => {
    void load();
    const channel = supabase
      .channel(`appointments-worklist-${user?.id ?? 'anonymous'}`)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'appointments',
        select: ['id', 'patient_id', 'scheduled_at', 'reason', 'status', 'department', 'practitioner_id', 'attending_officer_id', 'treatment_status', 'treatment_notes', 'consultation_type'],
      }, (payload) => {
        if (payload.eventType === 'INSERT') playWorkflowSound('info');
        if (payload.eventType === 'UPDATE' && String((payload.new as { treatment_status?: string }).treatment_status ?? '').toLowerCase() === 'completed') playWorkflowSound('success');
        void load(true);
      })
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR') toast({ title: 'Live appointment updates unavailable', description: 'The list will continue to work with manual refresh.', variant: 'destructive' });
      });
    return () => { void supabase.removeChannel(channel); };
  }, [user?.id]);

  const patientMap = useMemo(() => new Map(patients.map((p) => [p.id, p])), [patients]);
  const clinicianMap = useMemo(() => new Map(clinicians.map((c) => [c.id, c])), [clinicians]);

  const todayActive = useMemo(() => {
    const start = new Date(); start.setHours(0, 0, 0, 0);
    const end = new Date(); end.setHours(23, 59, 59, 999);
    return appts
      .filter((a) => {
        const time = new Date(a.scheduled_at).getTime();
        return time >= start.getTime() && time <= end.getTime() && activeStatuses.has(a.treatment_status || a.status || 'scheduled');
      })
      .sort((a, b) => new Date(a.scheduled_at).getTime() - new Date(b.scheduled_at).getTime());
  }, [appts]);

  const claimedToday = todayActive.filter((a) => (a.treatment_status || a.status) === 'claimed').length;
  const inTreatmentToday = todayActive.filter((a) => (a.treatment_status || a.status) === 'in_progress').length;
  const unassignedToday = todayActive.filter((a) => !a.attending_officer_id).length;

  const create = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!pid) return toast({ title: 'Select a patient', description: 'Choose the patient for this appointment.', variant: 'destructive' });
    if (!clinicianId) return toast({ title: 'Select a physician or specialist', description: 'Choose the clinician responsible for the appointment.', variant: 'destructive' });
    setSaving(true);
    const { data, error } = await supabase.rpc('create_appointment_workflow' as never, {
      _patient_id: pid,
      _scheduled_at: new Date(when).toISOString(),
      _department: 'Clinical Consultation',
      _reason: reason || null,
      _consultation_type: consultationType,
      _practitioner_id: clinicianId,
    } as never);
    setSaving(false);
    if (error) return toast({ title: 'Failed to schedule appointment', description: error.message, variant: 'destructive' });
    const created = data as unknown as Appointment;
    const patient = patientMap.get(pid);
    const clinician = clinicianMap.get(clinicianId);
    playWorkflowSound('success');
    toast({ title: 'Appointment scheduled', description: `${patient?.first_name ?? ''} ${patient?.last_name ?? ''} · ${consultationType}` });
    await notifyRoles(['practitioner', 'nurse', 'midwife', 'specialist_nurse', 'front_desk'], {
      title: 'New appointment',
      message: `${patient?.first_name ?? 'Patient'} ${patient?.last_name ?? ''} scheduled with ${clinician ? `${clinician.first_name ?? ''} ${clinician.last_name ?? ''}` : 'a clinician'} on ${new Date(when).toLocaleString()}`,
      severity: 'info',
      category: 'appointment',
      link: '/appointments',
      relatedPatientId: pid,
      relatedEntityId: created?.id,
    });
    setPid('');
    setConsultationType('General Consultation');
    setClinicianId('');
    setReason('');
    setShowScheduler(false);
    await load(true);
  };

  const claim = async (appointment: Appointment) => {
    if (!canClaim || appointment.attending_officer_id) return;
    setClaiming(true);
    const { error } = await supabase.rpc('claim_appointment' as never, { _appointment_id: appointment.id } as never);
    setClaiming(false);
    if (error) return toast({ title: 'Could not assign appointment', description: error.message, variant: 'destructive' });
    playWorkflowSound('success');
    toast({ title: 'Appointment assigned to you', description: 'You can now start the clinical encounter.' });
    await load(true);
    setSelected((current) => current?.id === appointment.id ? { ...current, attending_officer_id: currentUserId, treatment_status: 'claimed' } : current);
  };

  const startEncounter = async (appointment: Appointment) => {
    if (!canClaim) return;
    if (appointment.attending_officer_id !== currentUserId) {
      await claim(appointment);
    }
    setStartingEncounter(true);
    const { data, error } = await supabase.rpc('start_appointment_encounter' as never, {
      _appointment_id: appointment.id,
      _symptoms: null,
      _clerking_notes: null,
    } as never);
    setStartingEncounter(false);
    if (error) return toast({ title: 'Could not start encounter', description: error.message, variant: 'destructive' });
    playWorkflowSound('success');
    toast({ title: 'Clinical encounter started', description: 'The appointment is now in treatment.' });
    setSelected(null);
    await load(true);
    const encounterId = typeof data === 'string' ? data : String(data ?? '');
    navigate(`/encounters?patient=${encodeURIComponent(appointment.patient_id)}&appointment=${encodeURIComponent(appointment.id)}${encounterId ? `&encounter=${encodeURIComponent(encounterId)}` : ''}`);
  };

  const clinicianName = (id?: string | null) => {
    if (!id) return 'Unassigned';
    if (id === currentUserId) return 'You';
    const clinician = clinicianMap.get(id);
    return clinician ? `${clinician.first_name ?? ''} ${clinician.last_name ?? ''}`.trim() || 'Assigned clinician' : 'Assigned clinician';
  };

  const selectedStatus = selected?.treatment_status || selected?.status || 'scheduled';
  const selectedAssigned = selected?.attending_officer_id === currentUserId;

  const refresh = async () => {
    setRefreshing(true);
    await load(true);
    setRefreshing(false);
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <header className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Calendar className="w-6 h-6 text-primary" />
            <span className="text-xs font-medium uppercase tracking-wide text-primary">Care coordination</span>
          </div>
          <h1 className="text-2xl font-heading font-bold mt-1">Appointments</h1>
          <p className="text-muted-foreground max-w-2xl">Today’s active appointment queue. Completed, cancelled and no-show appointments leave this worklist automatically.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={() => void refresh()} disabled={loading || refreshing} className="btn-secondary inline-flex items-center gap-2">
            <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} /> Refresh
          </button>
          {canSchedule && <button type="button" onClick={() => setShowScheduler(true)} className="btn-primary inline-flex items-center gap-2">
            <Plus className="w-4 h-4" /> New appointment
          </button>}
        </div>
      </header>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3" aria-label="Today appointment counters">
        {[
          ['Active today', todayActive.length, 'text-primary', 'bg-primary/5'],
          ['Unassigned', unassignedToday, 'text-warning', 'bg-warning/5'],
          ['Claimed', claimedToday, 'text-info', 'bg-info/5'],
          ['In treatment', inTreatmentToday, 'text-success', 'bg-success/5'],
        ].map(([label, value, tone, surface]) => (
          <div key={String(label)} className={`card-medical ${surface} p-4`}>
            <p className="text-xs text-muted-foreground">{label}</p>
            <p className={`text-2xl font-bold mt-1 ${tone}`}>{value}</p>
          </div>
        ))}
      </div>

      <section className="card-medical p-0 overflow-hidden" aria-labelledby="today-appointments-heading">
        <div className="px-5 py-4 border-b border-border flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 id="today-appointments-heading" className="font-semibold">Today’s active appointments</h2>
            <p className="text-xs text-muted-foreground">Select any row to open the appointment and begin treatment.</p>
          </div>
          <span className="text-xs text-muted-foreground flex items-center gap-1"><Clock3 className="w-3.5 h-3.5" /> Live updates enabled</span>
        </div>

        <div className="hidden md:grid md:grid-cols-[1.1fr_1.5fr_1.35fr_1.5fr_1.35fr] gap-4 px-5 py-3 text-xs font-medium uppercase tracking-wide text-muted-foreground bg-muted/30">
          <span>Hospital ID</span><span>Patient</span><span>Consultation</span><span>Physician / Specialist</span><span>Date & time</span>
        </div>

        {loading ? (
          <div className="space-y-2 p-4" aria-live="polite">
            <div className="h-16 rounded-lg bg-muted animate-pulse" />
            <div className="h-16 rounded-lg bg-muted animate-pulse" />
          </div>
        ) : todayActive.length === 0 ? (
          <div className="py-14 px-5 text-center">
            <Calendar className="w-9 h-9 mx-auto text-muted-foreground mb-2" />
            <p className="font-medium">No active appointments today</p>
            <p className="text-sm text-muted-foreground mt-1">Use New appointment to schedule the next patient.</p>
          </div>
        ) : (
          <div className="divide-y divide-border">
            {todayActive.map((appointment) => {
              const patient = patientMap.get(appointment.patient_id);
              return (
                <button
                  key={appointment.id}
                  type="button"
                  onClick={() => setSelected(appointment)}
                  className="w-full text-left px-5 py-4 hover:bg-muted/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary transition-colors"
                  aria-label={`Open appointment for ${patient ? `${patient.first_name} ${patient.last_name}` : 'patient'}`}
                >
                  <div className="grid gap-2 md:grid-cols-[1.1fr_1.5fr_1.35fr_1.5fr_1.35fr] md:items-center">
                    <div><span className="md:hidden text-[11px] uppercase text-muted-foreground">Hospital ID</span><p className="font-mono text-sm">{patient?.patient_code ?? '—'}</p></div>
                    <div><span className="md:hidden text-[11px] uppercase text-muted-foreground">Patient</span><p className="font-medium">{patient ? `${patient.first_name} ${patient.last_name}` : 'Unknown patient'}</p></div>
                    <div><span className="md:hidden text-[11px] uppercase text-muted-foreground">Consultation</span><p className="text-sm">{appointment.consultation_type || 'General Consultation'}</p></div>
                    <div><span className="md:hidden text-[11px] uppercase text-muted-foreground">Physician / Specialist</span><p className="text-sm">{clinicianName(appointment.practitioner_id || appointment.attending_officer_id)}</p></div>
                    <div><span className="md:hidden text-[11px] uppercase text-muted-foreground">Date & time</span><p className="text-sm">{new Date(appointment.scheduled_at).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })}</p></div>
                  </div>
                </button>
              );
            })}
          </div>
        )}
      </section>

      {showScheduler && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true" aria-labelledby="new-appointment-heading">
          <form onSubmit={create} className="w-full max-w-2xl rounded-2xl bg-card border border-border shadow-xl p-6 space-y-5 max-h-[90vh] overflow-y-auto">
            <div className="flex items-start justify-between gap-4">
              <div><h2 id="new-appointment-heading" className="text-lg font-semibold">New appointment</h2><p className="text-sm text-muted-foreground mt-1">Enter the booking details and save the appointment.</p></div>
              <button type="button" onClick={() => setShowScheduler(false)} className="btn-secondary" aria-label="Close new appointment form"><X className="w-4 h-4" /></button>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="block space-y-1.5 text-sm sm:col-span-2">
                <span>Patient name</span>
                <select required value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full">
                  <option value="">Select patient…</option>
                  {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}
                </select>
              </label>
              <label className="block space-y-1.5 text-sm">
                <span>Consultation type</span>
                <select required value={consultationType} onChange={(e) => setConsultationType(e.target.value as (typeof consultationTypes)[number])} className="input-medical w-full">
                  {consultationTypes.map((type) => <option key={type}>{type}</option>)}
                </select>
              </label>
              <label className="block space-y-1.5 text-sm">
                <span>Physician / specialist</span>
                <select required value={clinicianId} onChange={(e) => setClinicianId(e.target.value)} className="input-medical w-full">
                  <option value="">Select clinician…</option>
                  {clinicians.map((clinician) => <option key={clinician.id} value={clinician.id}>{`${clinician.first_name ?? ''} ${clinician.last_name ?? ''}`.trim() || 'Unnamed clinician'}{clinician.specialization ? ` · ${clinician.specialization}` : ''}</option>)}
                </select>
              </label>
              <label className="block space-y-1.5 text-sm">
                <span>Date</span>
                <input required type="date" value={when.slice(0, 10)} onChange={(e) => setWhen(`${e.target.value}T${when.slice(11, 16)}`)} className="input-medical w-full" />
              </label>
              <label className="block space-y-1.5 text-sm">
                <span>Time</span>
                <input required type="time" value={when.slice(11, 16)} onChange={(e) => setWhen(`${when.slice(0, 10)}T${e.target.value}`)} className="input-medical w-full" />
              </label>
              <label className="block space-y-1.5 text-sm sm:col-span-2">
                <span>Clinical reason <span className="text-muted-foreground">(optional)</span></span>
                <textarea value={reason} onChange={(e) => setReason(e.target.value)} className="input-medical min-h-24 w-full" placeholder="Optional reason for the consultation" />
              </label>
            </div>
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setShowScheduler(false)} className="btn-secondary">Cancel</button>
              <button disabled={saving} type="submit" className="btn-primary">{saving ? 'Saving…' : 'Save appointment'}</button>
            </div>
          </form>
        </div>
      )}

      {selected && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true" aria-labelledby="appointment-detail-heading">
          <div className="w-full max-w-xl rounded-2xl bg-card border border-border shadow-xl p-6 space-y-5">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-xs uppercase tracking-wide text-primary">Appointment</p>
                <h2 id="appointment-detail-heading" className="text-xl font-semibold mt-1">{patientMap.get(selected.patient_id) ? `${patientMap.get(selected.patient_id)?.first_name} ${patientMap.get(selected.patient_id)?.last_name}` : 'Patient'}</h2>
                <p className="text-sm text-muted-foreground">{patientMap.get(selected.patient_id)?.patient_code ?? '—'} · {selected.consultation_type || 'General Consultation'}</p>
              </div>
              <button type="button" onClick={() => setSelected(null)} className="btn-secondary" aria-label="Close appointment"><X className="w-4 h-4" /></button>
            </div>
            <dl className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
              <div><dt className="text-muted-foreground">Physician / Specialist</dt><dd className="font-medium mt-1">{clinicianName(selected.practitioner_id || selected.attending_officer_id)}</dd></div>
              <div><dt className="text-muted-foreground">Date & time</dt><dd className="font-medium mt-1">{new Date(selected.scheduled_at).toLocaleString()}</dd></div>
              <div><dt className="text-muted-foreground">Status</dt><dd className="font-medium mt-1 capitalize">{selectedStatus.replaceAll('_', ' ')}</dd></div>
              <div><dt className="text-muted-foreground">Clinical reason</dt><dd className="font-medium mt-1">{selected.reason || 'Not provided'}</dd></div>
            </dl>
            <div className="rounded-lg border border-border bg-muted/20 p-4">
              <p className="text-sm font-medium">Treatment ownership</p>
              <p className="text-xs text-muted-foreground mt-1">
                {selected.attending_officer_id ? `Assigned to ${clinicianName(selected.attending_officer_id)}.` : 'No clinician has claimed this appointment yet.'}
              </p>
            </div>
            <div className="flex flex-wrap justify-end gap-2">
              <button type="button" onClick={() => navigate(`/patients/${selected.patient_id}`)} className="btn-secondary">Open patient</button>
              {canClaim && !selected.attending_officer_id && activeStatuses.has(selectedStatus) && (
                <button type="button" disabled={claiming} onClick={() => void claim(selected)} className="btn-secondary inline-flex items-center gap-2">
                  <UserCheck className="w-4 h-4" /> {claiming ? 'Assigning…' : 'Assign to me'}
                </button>
              )}
              {canClaim && activeStatuses.has(selectedStatus) && (
                <button type="button" disabled={startingEncounter} onClick={() => void startEncounter(selected)} className="btn-primary inline-flex items-center gap-2">
                  <Stethoscope className="w-4 h-4" /> {startingEncounter ? 'Starting…' : selectedAssigned ? 'Start encounter' : 'Assign & start encounter'}
                </button>
              )}
              <button type="button" onClick={() => setSelected(null)} className="btn-secondary inline-flex items-center gap-2"><CheckCircle2 className="w-4 h-4" /> Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
