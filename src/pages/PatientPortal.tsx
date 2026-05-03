import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Link } from 'react-router-dom';
import { FileText, Calendar, CreditCard, Video, HeartPulse } from 'lucide-react';

export default function PatientPortal() {
  const { user } = useAuth();
  const [patient, setPatient] = useState<any>(null);
  const [appts, setAppts] = useState<any[]>([]);
  const [sessions, setSessions] = useState<any[]>([]);
  const [invoices, setInvoices] = useState<any[]>([]);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data: p } = await supabase.from('patients').select('*').eq('user_id', user.id).maybeSingle();
      setPatient(p);
      if (p) {
        const [{ data: a }, { data: vs }, { data: inv }] = await Promise.all([
          supabase.from('appointments').select('*').eq('patient_id', p.id).order('scheduled_at', { ascending: false }).limit(10),
          supabase.from('video_sessions').select('*').eq('patient_id', p.id).order('scheduled_at', { ascending: false }).limit(10),
          supabase.from('invoices').select('*').eq('patient_id', p.id).order('created_at', { ascending: false }).limit(10),
        ]);
        setAppts(a ?? []); setSessions(vs ?? []); setInvoices(inv ?? []);
      }
    })();
  }, [user?.id]);

  if (!user) return null;

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold">Patient Portal</h1>
        <p className="text-muted-foreground">Your health information and services.</p>
      </div>

      {patient && (
        <div className="card-medical p-5">
          <p className="text-xs uppercase text-muted-foreground">Patient ID</p>
          <h2 className="text-xl font-semibold">{patient.patient_code}</h2>
          <p className="text-sm">{patient.first_name} {patient.last_name} · {patient.email}</p>
        </div>
      )}

      <div className="grid lg:grid-cols-2 gap-6">
        <div className="card-medical p-5">
          <h3 className="font-semibold flex items-center gap-2 mb-3"><Video className="w-4 h-4 text-primary" /> Telemedicine sessions</h3>
          <div className="space-y-2">
            {sessions.map((s) => (
              <div key={s.id} className="rounded-xl border border-border p-3">
                <p className="text-sm font-medium">{new Date(s.scheduled_at).toLocaleString()}</p>
                <p className="text-xs text-muted-foreground">Status: {s.status} · Payment {s.payment_received ? '✓' : 'pending'}</p>
                {s.payment_received ? (
                  <a href={`https://meet.jit.si/${s.room_name}`} target="_blank" rel="noreferrer" className="btn-primary text-xs mt-2 inline-flex">Join session</a>
                ) : (
                  <Link to="/billing" className="btn-ghost text-xs mt-2 inline-flex">Complete payment</Link>
                )}
              </div>
            ))}
            {sessions.length === 0 && <p className="text-sm text-muted-foreground">No telemedicine sessions yet.</p>}
          </div>
        </div>

        <div className="card-medical p-5">
          <h3 className="font-semibold flex items-center gap-2 mb-3"><Calendar className="w-4 h-4 text-primary" /> Appointments</h3>
          <div className="space-y-2">
            {appts.map((a) => (
              <div key={a.id} className="rounded-xl border border-border p-3 text-sm">
                <p className="font-medium">{new Date(a.scheduled_at).toLocaleString()}</p>
                <p className="text-xs text-muted-foreground">{a.department} · {a.status}</p>
              </div>
            ))}
            {appts.length === 0 && <p className="text-sm text-muted-foreground">No appointments.</p>}
          </div>
        </div>

        <div className="card-medical p-5">
          <h3 className="font-semibold flex items-center gap-2 mb-3"><CreditCard className="w-4 h-4 text-primary" /> Invoices</h3>
          <div className="space-y-2">
            {invoices.map((i) => (
              <div key={i.id} className="rounded-xl border border-border p-3 text-sm flex justify-between">
                <span>{i.invoice_number}</span>
                <span className={i.status === 'paid' ? 'text-success' : 'text-warning'}>GHS {i.total_amount} · {i.status}</span>
              </div>
            ))}
            {invoices.length === 0 && <p className="text-sm text-muted-foreground">No invoices.</p>}
          </div>
        </div>

        <div className="card-medical p-5 space-y-2">
          <h3 className="font-semibold flex items-center gap-2 mb-3"><FileText className="w-4 h-4 text-primary" /> Quick links</h3>
          <Link to="/records" className="block rounded-xl border border-border p-3 hover:bg-muted/50 text-sm">Medical Records</Link>
          <Link to="/notifications" className="block rounded-xl border border-border p-3 hover:bg-muted/50 text-sm">My Notifications</Link>
        </div>
      </div>
    </div>
  );
}
