import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Video, Plus, ExternalLink, Phone, AlertCircle } from 'lucide-react';

interface Patient { id: string; first_name: string; last_name: string }
interface Session {
  id: string; patient_id: string; practitioner_id: string | null; room_name: string;
  provider: string; scheduled_at: string; status: string;
  payment_required: boolean; payment_received: boolean;
}

export default function Telemedicine() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [pid, setPid] = useState('');
  const [scheduledAt, setScheduledAt] = useState(new Date(Date.now() + 60 * 60 * 1000).toISOString().slice(0, 16));

  const loadAll = async () => {
    const [{ data: pts, error: patientError }, { data: ss, error: sessionError }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name').limit(200),
      supabase.from('video_sessions').select('*').order('scheduled_at', { ascending: false }).limit(50),
    ]);
    if (patientError || sessionError) {
      toast({ title: 'Unable to load telemedicine workspace', description: patientError?.message ?? sessionError?.message, variant: 'destructive' });
      return;
    }
    setPatients(pts ?? []);
    setSessions((ss ?? []) as Session[]);
  };
  useEffect(() => { void loadAll(); }, []);

  const createSession = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return toast({ title: 'Select a patient', variant: 'destructive' });
    const { error } = await (supabase as any).rpc('schedule_video_session', {
      _patient_id: pid,
      _scheduled_at: new Date(scheduledAt).toISOString(),
      _provider: 'jitsi',
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Video session scheduled' });
    setPid('');
    void loadAll();
  };

  const markPaid = async (id: string) => {
    const { error } = await (supabase as any).rpc('mark_video_session_paid', { _session_id: id });
    if (error) return toast({ title: 'Payment update failed', description: error.message, variant: 'destructive' });
    void loadAll();
  };

  const startSession = async (s: Session) => {
    const { data, error } = await (supabase as any).rpc('start_video_session', { _session_id: s.id });
    if (error) return toast({ title: 'Unable to start session', description: error.message, variant: 'destructive' });
    const started = Array.isArray(data) ? data[0] : data;
    if (!started?.room_name) return toast({ title: 'Session room unavailable', variant: 'destructive' });
    if (started.provider !== 'jitsi') return toast({ title: 'Unsupported video provider', description: `Provider ${started.provider} is not configured.`, variant: 'destructive' });
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
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Video className="w-6 h-6 text-primary" /> Telemedicine</h1>
        <p className="text-muted-foreground">Video consultations with server-enforced payment and lifecycle controls.</p>
      </div>

      <div className="rounded-xl border border-info/30 bg-info/5 p-3 text-sm flex items-start gap-2">
        <AlertCircle className="w-4 h-4 text-info mt-0.5" />
        <div><strong>Clinical safety:</strong> video sessions are payment-gated and lifecycle transitions are authorized server-side. The current browser provider is Jitsi; replace it with an approved managed provider before handling regulated production telehealth traffic if your facility requires managed recording, identity assurance, or contractual controls.</div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[minmax(280px,360px)_1fr]">
        <form onSubmit={createSession} className="card-medical p-5 space-y-3 h-fit">
          <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> Schedule Session</h2>
          <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full">
            <option value="">Select patient…</option>
            {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
          </select>
          <input required type="datetime-local" value={scheduledAt} onChange={(e) => setScheduledAt(e.target.value)} className="input-medical w-full" />
          <button className="btn-primary w-full">Schedule</button>
        </form>

        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Sessions</h2>
          <div className="space-y-3">
            {sessions.map((s) => {
              const p = patients.find((x) => x.id === s.patient_id);
              return <div key={s.id} className="rounded-xl border border-border p-4">
                <div className="flex flex-col gap-2 sm:flex-row sm:justify-between sm:items-start">
                  <div className="min-w-0"><p className="font-medium truncate">{p ? `${p.first_name} ${p.last_name}` : '—'}</p><p className="text-xs text-muted-foreground">{new Date(s.scheduled_at).toLocaleString()} · Room: {s.room_name}</p></div>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-info/15 text-info self-start">{s.status}</span>
                </div>
                <div className="mt-3 flex flex-wrap gap-2 items-center">
                  {s.payment_required && !s.payment_received && <button type="button" onClick={() => void markPaid(s.id)} className="btn-ghost text-xs inline-flex items-center gap-1"><Phone className="w-3 h-3" /> Mark paid</button>}
                  {s.payment_received && <span className="text-xs text-success">✓ Paid</span>}
                  {s.status !== 'completed' && <button type="button" onClick={() => void startSession(s)} className="btn-primary text-xs inline-flex items-center gap-1"><ExternalLink className="w-3 h-3" /> Join call</button>}
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
