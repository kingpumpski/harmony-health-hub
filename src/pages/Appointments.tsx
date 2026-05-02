import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Calendar, Plus } from 'lucide-react';
import { notifyRoles, notify } from '@/lib/notifications';

interface Patient { id: string; first_name: string; last_name: string; user_id: string | null }
interface Appointment {
  id: string; patient_id: string; scheduled_at: string; reason: string | null;
  status: string; department: string | null;
}

export default function Appointments() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [appts, setAppts] = useState<Appointment[]>([]);
  const [pid, setPid] = useState('');
  const [when, setWhen] = useState(new Date(Date.now() + 60 * 60 * 1000).toISOString().slice(0, 16));
  const [dept, setDept] = useState('General Outpatient');
  const [reason, setReason] = useState('');

  const isStaff = user && user.role !== 'patient';

  const load = async () => {
    const [{ data: pts }, { data: aps }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name, user_id').limit(200),
      supabase.from('appointments').select('*').order('scheduled_at', { ascending: false }).limit(50),
    ]);
    setPatients(pts ?? []);
    setAppts(aps ?? []);
  };

  useEffect(() => {
    load();
    const ch = supabase.channel('appt-page')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, []);

  const create = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return;
    const { data, error } = await supabase.from('appointments').insert({
      patient_id: pid, scheduled_at: new Date(when).toISOString(),
      reason, department: dept, status: 'scheduled',
    }).select().single();
    if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Appointment scheduled' });

    const p = patients.find((x) => x.id === pid);
    const patientName = p ? `${p.first_name} ${p.last_name}` : 'patient';
    // Broadcast to relevant dashboards
    await notifyRoles(['practitioner', 'nurse', 'front_desk'], {
      title: 'New appointment',
      message: `${patientName} scheduled for ${dept} on ${new Date(when).toLocaleString()}`,
      severity: 'info', category: 'appointment', link: '/appointments',
      relatedPatientId: pid, relatedEntityId: data.id,
    });
    if (p?.user_id) {
      await notify({
        recipientUserId: p.user_id,
        title: 'Your appointment is booked',
        message: `${dept} on ${new Date(when).toLocaleString()}`,
        severity: 'success', category: 'appointment', link: '/patient-portal',
        relatedPatientId: pid, relatedEntityId: data.id,
      });
    }
    setReason('');
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
          <Calendar className="w-6 h-6 text-primary" /> Appointments
        </h1>
        <p className="text-muted-foreground">Schedule visits and notify the care team in real time.</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[360px_1fr]">
        {isStaff && (
          <form onSubmit={create} className="card-medical p-5 space-y-3 h-fit">
            <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New Appointment</h2>
            <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical w-full">
              <option value="">Select patient…</option>
              {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
            </select>
            <input type="datetime-local" value={when} onChange={(e) => setWhen(e.target.value)} className="input-medical w-full" />
            <select value={dept} onChange={(e) => setDept(e.target.value)} className="input-medical w-full">
              <option>General Outpatient</option>
              <option>Specialist Consultation</option>
              <option>Maternity</option>
              <option>Fertility</option>
              <option>Telemedicine</option>
            </select>
            <input value={reason} onChange={(e) => setReason(e.target.value)} className="input-medical w-full" placeholder="Reason (optional)" />
            <button className="btn-primary w-full">Schedule</button>
          </form>
        )}

        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Upcoming & Recent</h2>
          <div className="space-y-2">
            {appts.map((a) => {
              const p = patients.find((x) => x.id === a.patient_id);
              return (
                <div key={a.id} className="rounded-xl border border-border p-3 flex justify-between items-center">
                  <div>
                    <p className="font-medium text-sm">{p ? `${p.first_name} ${p.last_name}` : '—'}</p>
                    <p className="text-xs text-muted-foreground">{new Date(a.scheduled_at).toLocaleString()} · {a.department || 'General'}</p>
                    {a.reason && <p className="text-xs text-muted-foreground mt-0.5">{a.reason}</p>}
                  </div>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-muted text-muted-foreground">{a.status}</span>
                </div>
              );
            })}
            {appts.length === 0 && <p className="text-sm text-muted-foreground text-center py-6">No appointments yet.</p>}
          </div>
        </div>
      </div>
    </div>
  );
}
