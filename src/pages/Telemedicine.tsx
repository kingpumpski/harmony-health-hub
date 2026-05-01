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
    const [{ data: pts }, { data: ss }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name').limit(200),
      supabase.from('video_sessions').select('*').order('scheduled_at', { ascending: false }).limit(50),
    ]);
    setPatients(pts ?? []);
    setSessions(ss ?? []);
  };
  useEffect(() => { loadAll(); }, []);

  const createSession = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return;
    const room = `medicare-${Date.now().toString(36)}`;
    const { error } = await supabase.from('video_sessions').insert({
      patient_id: pid, practitioner_id: user?.id, room_name: room, provider: 'daily',
      scheduled_at: new Date(scheduledAt).toISOString(),
    });
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Video session scheduled' });
    setPid('');
    loadAll();
  };

  const markPaid = async (id: string) => {
    await supabase.from('video_sessions').update({ payment_received: true }).eq('id', id);
    loadAll();
  };

  const startSession = async (s: Session) => {
    if (s.payment_required && !s.payment_received) {
      return toast({ title: 'Payment required', description: 'Confirm payment before starting.', variant: 'destructive' });
    }
    await supabase.from('video_sessions').update({ status: 'active', started_at: new Date().toISOString() }).eq('id', s.id);
    // Open generic Jitsi room (works without API key — easy demo). Replace with Daily/LiveKit when SDK is wired.
    window.open(`https://meet.jit.si/${s.room_name}`, '_blank', 'noopener,noreferrer');
    loadAll();
  };

  const endSession = async (id: string) => {
    await supabase.from('video_sessions').update({ status: 'completed', ended_at: new Date().toISOString() }).eq('id', id);
    loadAll();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
          <Video className="w-6 h-6 text-primary" /> Telemedicine
        </h1>
        <p className="text-muted-foreground">Video consultations with payment-gated access.</p>
      </div>

      <div className="rounded-xl border border-info/30 bg-info/5 p-3 text-sm flex items-start gap-2">
        <AlertCircle className="w-4 h-4 text-info mt-0.5" />
        <div>
          Sessions currently use <strong>Jitsi Meet</strong> (no API key required) for demo. To switch to Daily.co / LiveKit / Twilio,
          add the provider SDK and replace the URL in <code>startSession</code>.
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[360px_1fr]">
        <form onSubmit={createSession} className="card-medical p-5 space-y-3 h-fit">
          <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> Schedule Session</h2>
          <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full">
            <option value="">Select patient…</option>
            {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
          </select>
          <input type="datetime-local" value={scheduledAt} onChange={(e) => setScheduledAt(e.target.value)} className="input-medical w-full" />
          <button className="btn-primary w-full">Schedule</button>
        </form>

        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Sessions</h2>
          <div className="space-y-3">
            {sessions.map((s) => {
              const p = patients.find((x) => x.id === s.patient_id);
              return (
                <div key={s.id} className="rounded-xl border border-border p-4">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium">{p ? `${p.first_name} ${p.last_name}` : '—'}</p>
                      <p className="text-xs text-muted-foreground">{new Date(s.scheduled_at).toLocaleString()} · Room: {s.room_name}</p>
                    </div>
                    <span className={`text-xs px-2 py-0.5 rounded-full ${
                      s.status === 'completed' ? 'bg-muted text-muted-foreground' :
                      s.status === 'active' ? 'bg-success/15 text-success' : 'bg-info/15 text-info'
                    }`}>{s.status}</span>
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2 items-center">
                    {s.payment_required && !s.payment_received && (
                      <button onClick={() => markPaid(s.id)} className="btn-ghost text-xs inline-flex items-center gap-1">
                        <Phone className="w-3 h-3" /> Mark paid
                      </button>
                    )}
                    {s.payment_received && <span className="text-xs text-success">✓ Paid</span>}
                    {s.status !== 'completed' && (
                      <button onClick={() => startSession(s)} className="btn-primary text-xs inline-flex items-center gap-1">
                        <ExternalLink className="w-3 h-3" /> Join call
                      </button>
                    )}
                    {s.status === 'active' && (
                      <button onClick={() => endSession(s.id)} className="btn-ghost text-xs">End</button>
                    )}
                  </div>
                </div>
              );
            })}
            {sessions.length === 0 && <p className="text-sm text-muted-foreground">No sessions yet.</p>}
          </div>
        </div>
      </div>
    </div>
  );
}
