// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useAuth } from '@/contexts/AuthContext';
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { Video, Plus, ExternalLink, AlertCircle, X } from 'lucide-react';
import PageHeader from '@/components/layout/PageHeader';

interface Patient { id: string; first_name: string; last_name: string }
interface Session {
  id: string; patient_id: string; practitioner_id: string | null; room_name: string;
  provider: string; scheduled_at: string; status: string;
  payment_required: boolean; payment_received: boolean; service_order_id: string | null;
}
interface BillingStatus { id: string; status: string }

function StaffTelemedicine() {
  const [patients, setPatients] = useState<Patient[]>([]);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [billing, setBilling] = useState<Record<string, string>>({});
  const [pid, setPid] = useState('');
  const [scheduledAt, setScheduledAt] = useState(new Date(Date.now() + 60 * 60 * 1000).toISOString().slice(0, 16));
  const [showScheduler, setShowScheduler] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const loadAll = async () => {
    const [{ data: pts, error: patientError }, { data: ss, error: sessionError }] = await Promise.all([
      searchPatientDirectory('', 200).then(({ data }) => ({ data, error: null })),
      supabase.from('video_sessions').select('id,patient_id,practitioner_id,room_name,provider,scheduled_at,status,payment_required,payment_received,service_order_id').order('scheduled_at', { ascending: false }).limit(50),
    ]);
    if (patientError || sessionError) {
      toast({ title: 'Unable to load telemedicine workspace', description: patientError?.message ?? sessionError?.message, variant: 'destructive' });
      return;
    }
    setPatients(pts ?? []);
    const loaded = (ss ?? []) as Session[];
    setSessions(loaded);

    const orderIds = loaded.map((s) => s.service_order_id).filter((id): id is string => Boolean(id));
    if (!orderIds.length) return setBilling({});
    const { data: orders, error: orderError } = await (supabase as any).from('service_orders').select('id,status').in('id', orderIds);
    if (orderError) {
      toast({ title: 'Unable to load telemedicine billing status', description: orderError.message, variant: 'destructive' });
      return;
    }
    setBilling(Object.fromEntries(((orders ?? []) as BillingStatus[]).map((o) => [o.id, o.status])));
  };
  useEffect(() => {
    void loadAll();
    const channel = supabase.channel('telemedicine-workspace').on('postgres_changes', { event: '*', schema: 'public', table: 'video_sessions' }, () => { void loadAll(); }).subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, []);

  const createSession = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return toast({ title: 'Select a patient', variant: 'destructive' });
    const { error } = await (supabase as any).rpc('schedule_video_session', {
      _patient_id: pid,
      _scheduled_at: new Date(scheduledAt).toISOString(),
      _provider: 'jitsi',
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Video session scheduled', description: 'Accounts must release the telemedicine service order in Billing before the consultation can start.' });
    setPid('');
    setShowScheduler(false);
    void loadAll();
  };

  const startSession = async (s: Session) => {
    if (s.provider !== 'jitsi') return toast({ title: 'Unsupported video provider', description: `Provider ${s.provider} is not configured.`, variant: 'destructive' });
    if (s.status === 'active') {
      window.open(`https://meet.jit.si/${s.room_name}`, '_blank', 'noopener,noreferrer');
      return;
    }
    const billingStatus = s.service_order_id ? billing[s.service_order_id] : undefined;
    const released = billingStatus === 'released' || billingStatus === 'in_progress' || billingStatus === 'completed';
    const paymentSatisfied = !s.payment_required || s.payment_received || released;
    if (!['scheduled', 'ready'].includes(s.status) || !paymentSatisfied) {
      return toast({ title: 'Session not ready', description: 'The session must be assigned, within its start lifecycle, and released by Billing before joining.', variant: 'destructive' });
    }
    const { data, error } = await (supabase as any).rpc('start_video_session', { _session_id: s.id });
    if (error) return toast({ title: 'Unable to start session', description: error.message, variant: 'destructive' });
    const started = Array.isArray(data) ? data[0] : data;
    if (!started?.room_name) return toast({ title: 'Session room unavailable', variant: 'destructive' });
    window.open(`https://meet.jit.si/${started.room_name}`, '_blank', 'noopener,noreferrer');
    void loadAll();
  };

  const endSession = async (id: string) => {
    const { error } = await (supabase as any).rpc('end_video_session', { _session_id: id });
    if (error) return toast({ title: 'Unable to end session', description: error.message, variant: 'destructive' });
    void loadAll();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        icon={<Video className="w-6 h-6" aria-hidden="true" />}
        eyebrow="Care coordination"
        title="Telemedicine"
        description="Video consultations with server-enforced billing and lifecycle controls."
        primaryAction={<button type="button" onClick={() => setShowScheduler(true)} className="btn-primary inline-flex items-center gap-2"><Plus className="w-4 h-4" /> Schedule Session</button>}
        onRefresh={() => { setRefreshing(true); void loadAll().finally(() => setRefreshing(false)); }}
        refreshing={refreshing}
      />

      <div className="rounded-xl border border-info/30 bg-info/5 p-3 text-sm flex items-start gap-2">
        <AlertCircle className="w-4 h-4 text-info mt-0.5 shrink-0" />
        <div><strong>Clinical safety:</strong> every scheduled consultation creates a billable TELEMEDICINE service order. Accounts releases it through Billing after payment or an authorized override; the practitioner cannot start the session before release. The current browser provider is Jitsi; replace it with an approved managed provider before regulated production telehealth traffic if your facility requires managed recording, identity assurance, or contractual controls.</div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[minmax(280px,360px)_1fr]">
        {showScheduler && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true" aria-labelledby="schedule-session-heading">
          <form onSubmit={createSession} className="card-medical w-full max-w-lg space-y-4 p-6 shadow-xl">
            <div className="flex items-start justify-between gap-4"><div><h2 id="schedule-session-heading" className="font-semibold">Schedule Session</h2><p className="mt-1 text-sm text-muted-foreground">Create a billable telemedicine consultation.</p></div><button type="button" className="btn-ghost" aria-label="Close schedule session" onClick={() => setShowScheduler(false)}><X className="h-4 w-4" /></button></div>
            <select required value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}</select>
            <input required type="datetime-local" value={scheduledAt} onChange={(e) => setScheduledAt(e.target.value)} className="input-medical w-full" />
            <div className="flex justify-end gap-2"><button type="button" className="btn-secondary" onClick={() => setShowScheduler(false)}>Cancel</button><button className="btn-primary">Schedule</button></div>
          </form>
        </div>}

        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Sessions</h2>
          <div className="space-y-3">
            {sessions.map((s) => {
              const p = patients.find((x) => x.id === s.patient_id);
              const billingStatus = s.service_order_id ? billing[s.service_order_id] : undefined;
              const released = billingStatus === 'released' || billingStatus === 'in_progress' || billingStatus === 'completed';
              const canJoin = s.status === 'active' || (['scheduled', 'ready'].includes(s.status) && (!s.payment_required || s.payment_received || released));
              return <div key={s.id} className="rounded-xl border border-border p-4">
                <div className="flex flex-col gap-2 sm:flex-row sm:justify-between sm:items-start">
                  <div className="min-w-0"><p className="font-medium truncate">{p ? `${p.first_name} ${p.last_name}` : '—'}</p><p className="text-xs text-muted-foreground">{new Date(s.scheduled_at).toLocaleString()} · Room: {s.room_name}</p></div>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-info/15 text-info self-start">{s.status}</span>
                </div>
                <div className="mt-3 flex flex-wrap gap-2 items-center">
                  {s.payment_required && !released && <span className="text-xs text-warning">Billing release required</span>}
                  {released && <span className="text-xs text-success">✓ Billing released</span>}
                  {canJoin && <button type="button" onClick={() => void startSession(s)} className="btn-primary text-xs inline-flex items-center gap-1"><ExternalLink className="w-3 h-3" /> Join call</button>}
                  {s.status === 'active' && <button type="button" onClick={() => void endSession(s.id)} className="btn-ghost text-xs">End</button>}
                </div>
              </div>;
            })}
            {sessions.length === 0 && <p className="text-sm text-muted-foreground">No sessions yet.</p>}
          </div>
        </div>
      </div>
    </div>
  );
}

function PatientTelemedicine() {
  const [sessions, setSessions] = useState<any[]>([]);
  const [clinicians, setClinicians] = useState<any[]>([]);
  const [open, setOpen] = useState(false);
  const [clinicianId, setClinicianId] = useState('');
  const [scheduledAt, setScheduledAt] = useState(new Date(Date.now() + 24*60*60*1000).toISOString().slice(0,16));
  const [reason, setReason] = useState('');

  const load = async (at = scheduledAt) => {
    const [{ data: rows, error: sessionError }, { data: staff, error: clinicianError }] = await Promise.all([
      supabase.rpc('get_patient_portal_video_sessions', { _limit: 50 }),
      supabase.rpc('get_patient_telemedicine_clinicians', { _scheduled_at: new Date(at).toISOString() }),
    ]);
    if (sessionError || clinicianError) {
      toast({ title: 'Service temporarily unavailable', description: sessionError?.message ?? clinicianError?.message ?? 'Telemedicine information could not be loaded.', variant: 'destructive' });
      return;
    }
    setSessions(rows ?? []);
    setClinicians(staff ?? []);
    if (staff?.length && !staff.some((c: any) => c.id === clinicianId)) setClinicianId('');
  };
  useEffect(() => { void load(scheduledAt); }, []);
  useEffect(() => { if (open) void load(scheduledAt); }, [scheduledAt, open]);

  const request = async (e: React.FormEvent) => {
    e.preventDefault();
    const { error } = await (supabase as any).rpc('request_patient_telemedicine_session', {
      _clinician_id: clinicianId, _scheduled_at: new Date(scheduledAt).toISOString(), _reason: reason.trim(),
    });
    if (error) {
      toast({ title: 'Unable to submit request', description: 'Service temporarily unavailable. Please try again later.' });
      return;
    }
    toast({ title: 'Telemedicine request submitted', description: 'A clinician will review your preferred time.' });
    setOpen(false); setClinicianId(''); setReason(''); void load();
  };

  const now = Date.now();
  const upcoming = sessions.filter(s => new Date(s.scheduled_at).getTime() >= now).sort((a,b)=>new Date(a.scheduled_at).getTime()-new Date(b.scheduled_at).getTime());
  const past = sessions.filter(s => new Date(s.scheduled_at).getTime() < now).sort((a,b)=>new Date(b.scheduled_at).getTime()-new Date(a.scheduled_at).getTime());

  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:justify-between">
      <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Video className="w-6 h-6 text-primary" /> Telemedicine</h1><p className="text-muted-foreground">Request and join your telemedicine consultations.</p></div>
      <button className="btn-primary inline-flex items-center gap-2" onClick={()=>setOpen(true)}><Plus className="w-4 h-4"/> Request New Telemedicine Session</button>
    </div>
    <div className="card-medical p-5"><h2 className="font-semibold mb-3">Upcoming sessions</h2>{upcoming.length ? upcoming.map(s=><div key={s.id} className="rounded-xl border border-border p-4 mb-3"><div className="flex justify-between gap-3"><div><p className="font-medium">{new Date(s.scheduled_at).toLocaleString()}</p><p className="text-sm text-muted-foreground">{s.notes || 'Telemedicine consultation'}</p></div><span className="text-xs rounded-full bg-info/15 px-2 py-1">{s.status}</span></div>{s.status === 'active' && s.room_name && <a href={`https://meet.jit.si/${s.room_name}`} target="_blank" rel="noreferrer" className="btn-primary text-xs mt-3 inline-flex items-center gap-1"><ExternalLink className="w-3 h-3"/> Join session</a>}</div>) : <p className="text-sm text-muted-foreground">You have no upcoming telemedicine sessions. Request one here.</p>}</div>
    <div className="card-medical p-5"><h2 className="font-semibold mb-3">Past sessions</h2>{past.length ? past.map(s=><div key={s.id} className="rounded-xl border border-border p-4 mb-3"><p className="font-medium">{new Date(s.scheduled_at).toLocaleString()}</p><p className="text-sm text-muted-foreground">{s.notes || 'Telemedicine consultation'} · {s.status}</p></div>) : <p className="text-sm text-muted-foreground">You have no past telemedicine sessions.</p>}</div>
    {open && <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4"><form onSubmit={request} className="card-medical bg-background p-6 w-full max-w-lg space-y-4"><h2 className="text-lg font-semibold">Request New Telemedicine Session</h2><div><label className="mb-1 block text-sm font-medium" htmlFor="telemedicine-clinician">Available clinician</label><select id="telemedicine-clinician" required value={clinicianId} onChange={e=>setClinicianId(e.target.value)} className="input-medical w-full" disabled={!clinicians.length}><option value="">{clinicians.length ? "Select doctor…" : "No clinicians available for this time"}</option>{clinicians.map(c=><option key={c.id} value={c.id}>{c.first_name} {c.last_name}{c.specialization ? ` · ${c.specialization}` : ""}{c.is_on_duty ? " · On duty" : ""}</option>)}</select>{!clinicians.length && <p className="mt-1 text-xs text-muted-foreground">Choose another future time. Clinicians are matched to the selected facility and on-duty shift when shift schedules are configured.</p>}</div><div><label className="mb-1 block text-sm font-medium" htmlFor="telemedicine-scheduled-at">Preferred date and time</label><input id="telemedicine-scheduled-at" required type="datetime-local" min={new Date().toISOString().slice(0,16)} value={scheduledAt} onChange={e=>setScheduledAt(e.target.value)} className="input-medical w-full"/></div><textarea required value={reason} onChange={e=>setReason(e.target.value)} className="input-medical w-full min-h-28" placeholder="Reason for the visit"/><div className="flex justify-end gap-2"><button type="button" className="btn-ghost" onClick={()=>setOpen(false)}>Cancel</button><button className="btn-primary">Submit request</button></div></form></div>}
  </div>;
}

export default function Telemedicine() { const { user } = useAuth(); return user?.roles?.includes('patient') ? <PatientTelemedicine /> : <StaffTelemedicine />; }
