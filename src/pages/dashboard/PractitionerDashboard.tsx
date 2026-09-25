import { useCallback, useEffect, useState } from 'react';
import { Activity, AlertTriangle, BedDouble, Calendar, CheckCircle2, ClipboardCheck, Clock3, Image as ImageIcon, FlaskConical, Stethoscope, Users, BellRing, Baby, Brain } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

type Metric = { label: string; value: number | null; description: string; href: string; icon: typeof Activity; tone: string };

export default function PractitionerDashboard() {
  const { user } = useAuth();
  const [metrics, setMetrics] = useState<Metric[]>([]);
  const [loading, setLoading] = useState(true);
  const [attention, setAttention] = useState(0);

  const load = useCallback(async () => {
    if (!user?.id) return;
    setLoading(true);
    const start = new Date(); start.setHours(0, 0, 0, 0);
    const end = new Date(); end.setHours(23, 59, 59, 999);
    const [appointments, emergency, admissions, icu, alerts, notifications, labOrders, imagingOrders, serviceOrders] = await Promise.all([
      getOperationalWorkspace('appointments', 200),
      getOperationalWorkspace('emergency', 100),
      supabase.from('admissions').select('id', { count: 'exact', head: true }).eq('status', 'admitted'),
      supabase.from('admissions').select('id', { count: 'exact', head: true }).eq('status', 'admitted').ilike('ward', '%icu%'),
      supabase.from('vital_alerts').select('id', { count: 'exact', head: true }).is('acknowledged_at', null),
      (supabase as any).rpc('get_workflow_notifications', { _limit: 200 }),
    ]);
    if (appointments.error) toast({ title: 'Appointment counters unavailable', description: appointments.error.message, variant: 'destructive' });
    if (emergency.error) toast({ title: 'Emergency counters unavailable', description: emergency.error.message, variant: 'destructive' });
    if (admissions.error) toast({ title: 'Inpatient counter unavailable', description: admissions.error.message, variant: 'destructive' });
    if (alerts.error) toast({ title: 'Critical alert counter unavailable', description: alerts.error.message, variant: 'destructive' });
    if (labOrders.error || imagingOrders.error || serviceOrders.error) toast({ title: 'Department counters partially unavailable', description: 'Some diagnostic/service counters could not be refreshed.', variant: 'destructive' });
    const rows = Array.isArray(appointments.data) ? appointments.data as Array<{ scheduled_at?: string; status?: string; treatment_status?: string }> : [];
    const today = rows.filter((a) => { const t = new Date(a.scheduled_at ?? '').getTime(); return t >= start.getTime() && t <= end.getTime(); });
    const active = today.filter((a) => !['completed', 'cancelled', 'no_show'].includes(String(a.treatment_status ?? a.status ?? 'scheduled')));
    const review = rows.filter((a) => ['checked_in', 'review'].includes(String(a.status ?? '').toLowerCase()) || ['checked_in', 'review'].includes(String(a.treatment_status ?? '').toLowerCase()));
    const completed = today.filter((a) => String(a.treatment_status ?? a.status ?? '').toLowerCase() === 'completed');
    const emergencyRows = Array.isArray(emergency.data) ? emergency.data as unknown[] : [];
    const notificationRows = Array.isArray(notifications.data) ? notifications.data as Array<{ is_read?: boolean; severity?: string }> : [];
    const unreadNotifications = notificationRows.filter((n) => !n.is_read);
    const highAttention = unreadNotifications.filter((n) => ['critical', 'warning', 'high'].includes(String(n.severity ?? '').toLowerCase())).length;
    setAttention(highAttention);
    setMetrics([
      { label: 'Appointments', value: active.length, description: 'Active today', href: '/appointments', icon: Calendar, tone: 'text-primary bg-primary/5' },
      { label: 'Pending reviews', value: review.length, description: 'Checked-in / review queue', href: '/appointments', icon: ClipboardCheck, tone: 'text-warning bg-warning/5' },
      { label: 'Critical / emergency', value: (alerts.count ?? 0) + emergencyRows.length, description: 'Needs clinical attention', href: '/vitals', icon: AlertTriangle, tone: 'text-critical bg-critical/5' },
      { label: 'Completed', value: completed.length, description: 'Completed today', href: '/appointments', icon: CheckCircle2, tone: 'text-success bg-success/5' },
      { label: 'Inpatients', value: admissions.count ?? null, description: 'Currently admitted', href: '/inpatient', icon: BedDouble, tone: 'text-info bg-info/5' },
      { label: 'ICU', value: icu.count ?? null, description: 'Admitted in ICU', href: '/inpatient', icon: Activity, tone: 'text-critical bg-critical/5' },
      { label: 'Notifications', value: notificationRows.filter((n) => !n.is_read).length, description: 'Unread workflow events', href: '/notifications', icon: BellRing, tone: 'text-warning bg-warning/5' },
      { label: 'Laboratory', value: labOrders.error ? null : (labOrders.data?.length ?? 0), description: 'Open diagnostic work', href: '/laboratory', icon: FlaskConical, tone: 'text-info bg-info/5' },
      { label: 'Radiology', value: imagingOrders.error ? null : (imagingOrders.data?.length ?? 0), description: 'Open imaging work', href: '/radiology', icon: ImageIcon, tone: 'text-primary bg-primary/5' },
      { label: 'Services', value: serviceOrders.error ? null : (serviceOrders.data?.length ?? 0), description: 'Open service orders', href: '/department-queue', icon: ClipboardCheck, tone: 'text-warning bg-warning/5' },
    ]);
    setLoading(false);
  }, [user?.id]);

  useEffect(() => {
    void load();
    if (!user?.id) return;
    const channel = supabase.channel(`practitioner-dashboard-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'admissions' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'vital_alerts' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'lab_orders' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'imaging_orders' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders' }, () => void load())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load, user?.id]);

  if (!user) return null;
  return <div className="space-y-6 animate-fade-in">
    <section className="rounded-3xl border border-border bg-card p-5 shadow-sm sm:p-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div><p className="text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">Clinical command · Practitioner</p><h1 className="mt-1 text-2xl font-heading font-bold tracking-tight">Today's patient-care work</h1><p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">Appointments, clinical reviews, critical attention and inpatient activity are surfaced here so the next action is visible without opening multiple pages.</p></div>
        <div className="flex flex-wrap gap-2"><Link to="/appointments" className="btn-primary inline-flex items-center gap-2"><Calendar className="h-4 w-4" /> My schedule</Link><Link to="/encounters" className="btn-secondary inline-flex items-center gap-2"><Stethoscope className="h-4 w-4" /> Encounters</Link><button type="button" onClick={() => void load()} className="btn-ghost inline-flex items-center gap-2" aria-label="Refresh practitioner dashboard"><Clock3 className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} /> Refresh</button></div>
      </div>
    </section>
    {attention > 0 && <section className="rounded-2xl border border-critical/30 bg-critical/5 p-4" role="status" aria-live="polite"><div className="flex items-center justify-between gap-3"><div><p className="text-sm font-semibold text-critical">Clinical attention required</p><p className="mt-1 text-xs text-muted-foreground">{attention} unread high-priority workflow event{attention === 1 ? '' : 's'} require acknowledgement.</p></div><Link to="/notifications" className="btn-secondary">Review alerts</Link></div></section>}
    <section className="grid grid-cols-2 gap-3 md:grid-cols-4" aria-label="Clinical priority counters">
      {metrics.map(({ label, value, description, href, icon: Icon, tone }) => <Link key={label} to={href} className={`group rounded-2xl border border-border p-4 transition-all hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-sm ${tone}`}><div className="flex items-start justify-between gap-2"><p className="text-xs font-medium text-muted-foreground">{label}</p><Icon className="h-4 w-4 shrink-0" /></div><p className="mt-2 text-3xl font-bold tabular-nums">{value ?? '—'}</p><p className="mt-1 text-[11px] text-muted-foreground">{description}</p></Link>)}
    </section>
    <section className="grid grid-cols-1 gap-4 lg:grid-cols-3">
      <Link to="/appointments" className="card-medical p-5 hover:border-primary/40 transition-colors"><Calendar className="mb-2 h-5 w-5 text-primary" /><h2 className="font-semibold">Appointment worklist</h2><p className="mt-1 text-sm text-muted-foreground">Claim a patient, start treatment and open the encounter directly from the schedule.</p></Link>
      <Link to="/clinical-results" className="card-medical p-5 hover:border-primary/40 transition-colors"><ImageIcon className="mb-2 h-5 w-5 text-primary" /><h2 className="font-semibold">Results review</h2><p className="mt-1 text-sm text-muted-foreground">Review completed diagnostics and acknowledge results assigned to your clinical workflow.</p></Link>
      <Link to="/inpatient" className="card-medical p-5 hover:border-primary/40 transition-colors"><Users className="mb-2 h-5 w-5 text-info" /><h2 className="font-semibold">Inpatient continuity</h2><p className="mt-1 text-sm text-muted-foreground">Move from encounter decisions into admission, ward and ongoing inpatient care.</p></Link>
    </section>
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
      <Link to="/department-queue" className="card-medical p-4 hover:border-primary/40 transition-colors"><ClipboardCheck className="w-5 h-5 text-primary mb-2" /><p className="font-semibold">Department Queue</p><p className="text-sm text-muted-foreground mt-1">Coordinate service flow and patient movement.</p></Link>
      <Link to="/ai-clinical" className="card-medical p-4 hover:border-primary/40 transition-colors"><Brain className="w-5 h-5 text-primary mb-2" /><p className="font-semibold">AI Clinical Hub</p><p className="text-sm text-muted-foreground mt-1">Open assisted review with clinician oversight.</p></Link>
      <Link to="/fertility" className="card-medical p-4 hover:border-primary/40 transition-colors"><Baby className="w-5 h-5 text-primary mb-2" /><p className="font-semibold">Fertility Services</p><p className="text-sm text-muted-foreground mt-1">Move directly into fertility-specific workflows.</p></Link>
    </div>
  </div>;
}
