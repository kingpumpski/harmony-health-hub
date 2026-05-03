import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Link } from 'react-router-dom';
import { FileText, Calendar, CreditCard, Video, Sparkles, Printer, Volume2 } from 'lucide-react';
import { toast } from '@/hooks/use-toast';
import { playSuccessSound } from '@/lib/sounds';

export default function PatientPortal() {
  const { user } = useAuth();
  const [patient, setPatient] = useState<any>(null);
  const [appts, setAppts] = useState<any[]>([]);
  const [sessions, setSessions] = useState<any[]>([]);
  const [invoices, setInvoices] = useState<any[]>([]);
  const [reports, setReports] = useState<any[]>([]);
  const [requesting, setRequesting] = useState(false);

  const loadReports = async (patientId: string) => {
    const { data } = await supabase
      .from('ai_report_requests')
      .select('*')
      .eq('patient_id', patientId)
      .order('created_at', { ascending: false })
      .limit(10);
    setReports(data ?? []);
  };

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
        loadReports(p.id);
      }
    })();
  }, [user?.id]);

  const requestAIReport = async () => {
    if (!patient) return;
    setRequesting(true);
    try {
      // 1. Create the request row
      const { data: req, error: insErr } = await supabase
        .from('ai_report_requests')
        .insert({ patient_id: patient.id, requested_by: user?.id, report_type: 'medical_summary', status: 'processing' })
        .select()
        .single();
      if (insErr) throw insErr;

      // 2. Generate via existing edge function
      const { data, error } = await supabase.functions.invoke('ai-clinical-assist', {
        body: { mode: 'report', patientId: patient.id },
      });
      if (error || data?.error) throw new Error(data?.error ?? error?.message ?? 'AI failed');

      // 3. Save result
      await supabase.from('ai_report_requests').update({
        status: 'completed', content: data.content, completed_at: new Date().toISOString(),
      }).eq('id', req.id);

      playSuccessSound();
      toast({ title: '✓ Report ready', description: 'Your AI medical report is available below.' });
      loadReports(patient.id);
    } catch (e: any) {
      toast({ title: 'Report failed', description: e.message, variant: 'destructive' });
    }
    setRequesting(false);
  };

  const speakReport = (text: string) => {
    const u = new SpeechSynthesisUtterance(text.replace(/[#*_`]/g, ''));
    speechSynthesis.cancel();
    speechSynthesis.speak(u);
  };

  const printReport = (text: string) => {
    const w = window.open('', '_blank');
    if (!w) return;
    w.document.write(`<pre style="font-family:Georgia,serif;white-space:pre-wrap;padding:32px;max-width:800px;margin:auto">${text.replace(/</g, '&lt;')}</pre>`);
    w.document.close();
    w.print();
  };

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

      {/* AI Medical Report (client-facing) */}
      {patient && (
        <div className="card-medical p-5 bg-gradient-to-br from-primary/5 to-accent/5 border-primary/20">
          <div className="flex items-start justify-between gap-4 flex-wrap">
            <div>
              <h3 className="font-semibold flex items-center gap-2"><Sparkles className="w-4 h-4 text-primary" /> AI Medical Report</h3>
              <p className="text-sm text-muted-foreground mt-1">
                Generate a comprehensive summary of your encounters, vitals, labs and treatment history.
              </p>
            </div>
            <button onClick={requestAIReport} disabled={requesting} className="btn-primary text-sm inline-flex items-center gap-2">
              <Sparkles className="w-4 h-4" /> {requesting ? 'Generating…' : 'Request report'}
            </button>
          </div>

          {reports.length > 0 && (
            <div className="space-y-3 mt-4">
              {reports.map((r) => (
                <div key={r.id} className="rounded-xl border border-border bg-background p-4">
                  <div className="flex justify-between items-center text-xs text-muted-foreground mb-2">
                    <span>Requested {new Date(r.created_at).toLocaleString()}</span>
                    <span className={r.status === 'completed' ? 'text-success' : r.status === 'failed' ? 'text-critical' : 'text-warning'}>
                      {r.status}
                    </span>
                  </div>
                  {r.status === 'completed' && r.content && (
                    <>
                      <div className="prose prose-sm max-w-none whitespace-pre-wrap text-sm">{r.content}</div>
                      <div className="flex gap-2 mt-3">
                        <button onClick={() => printReport(r.content)} className="btn-ghost text-xs inline-flex items-center gap-1"><Printer className="w-3 h-3" /> Print</button>
                        <button onClick={() => speakReport(r.content)} className="btn-ghost text-xs inline-flex items-center gap-1"><Volume2 className="w-3 h-3" /> Read aloud</button>
                      </div>
                    </>
                  )}
                  {r.status === 'failed' && <p className="text-xs text-critical">{r.error ?? 'Failed to generate.'}</p>}
                </div>
              ))}
            </div>
          )}
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
          <Link to="/outside-lab" className="block rounded-xl border border-border p-3 hover:bg-muted/50 text-sm">Upload Outside Diagnostics</Link>
        </div>
      </div>
    </div>
  );
}
