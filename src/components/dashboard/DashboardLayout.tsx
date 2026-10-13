import { useCallback, useEffect, useState } from 'react';
import { Activity, CalendarDays, ClipboardList, RefreshCw, Users, ArrowRight, AlertTriangle } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import RefreshButton from '@/components/ui/RefreshButton';

export type SpecialistKind = 'physiotherapy' | 'ophthalmology' | 'dental' | 'dietetics';

type Config = {
  title: string;
  eyebrow: string;
  description: string;
  table: string;
  reviewSpecialty: SpecialistKind;
  departmentMatch: string;
  primaryHref: string;
  primaryLabel: string;
  extraTable?: string;
  extraLabel?: string;
  extraHref?: string;
};

const configs: Record<SpecialistKind, Config> = {
  physiotherapy: {
    title: 'Physiotherapy workspace', eyebrow: 'Specialist command · Physiotherapy',
    description: 'Initial assessments, treatment plans and review sessions in one facility-scoped worklist.',
    table: 'physio_assessments', reviewSpecialty: 'physiotherapy', departmentMatch: 'physio',
    primaryHref: '/specialist-assessments?specialty=physiotherapy', primaryLabel: 'New assessment',
    extraTable: 'physio_treatment_plans', extraLabel: 'Active treatment plans', extraHref: '/appointments'
  },
  ophthalmology: {
    title: 'Ophthalmology workspace', eyebrow: 'Specialist command · Ophthalmology',
    description: 'Eye assessments, follow-up reviews and diagnostic workflow visibility.',
    table: 'ophthalmology_assessments', reviewSpecialty: 'ophthalmology', departmentMatch: 'ophthalm',
    primaryHref: '/specialist-assessments?specialty=ophthalmology', primaryLabel: 'New eye assessment',
    extraTable: 'appointments', extraLabel: 'Upcoming clinics', extraHref: '/appointments'
  },
  dental: {
    title: 'Dental workspace', eyebrow: 'Specialist command · Dentistry',
    description: 'Dental assessments, tooth-chart records and pending procedure follow-up.',
    table: 'dental_assessments', reviewSpecialty: 'dental', departmentMatch: 'dent',
    primaryHref: '/specialist-assessments?specialty=dental', primaryLabel: 'New dental assessment',
    extraTable: 'dental_assessments', extraLabel: 'Procedure records', extraHref: '/dental'
  },
  dietetics: {
    title: 'Dietetics workspace', eyebrow: 'Specialist command · Dietetics',
    description: 'Nutritional assessments, active meal plans and review-session visibility.',
    table: 'dietary_assessments', reviewSpecialty: 'dietetics', departmentMatch: 'diet',
    primaryHref: '/specialist-assessments?specialty=dietetics', primaryLabel: 'New dietary assessment',
    extraTable: 'dietary_meal_orders', extraLabel: 'Patients on specialized diets', extraHref: '/dietary-plans'
  }
};

type WorkItem = { id: string; patient_id: string; created_at: string; updated_at?: string };

export default function DashboardLayout({ specialty }: { specialty: SpecialistKind }) {
  const { user } = useAuth();
  const config = configs[specialty];
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [assessmentsToday, setAssessmentsToday] = useState<number | null>(null);
  const [pendingReviews, setPendingReviews] = useState<number | null>(null);
  const [extraCount, setExtraCount] = useState<number | null>(null);
  const [appointmentsToday, setAppointmentsToday] = useState<number | null>(null);
  const [items, setItems] = useState<WorkItem[]>([]);

  const load = useCallback(async () => {
    if (!user?.id) { setLoading(false); return; }
    setLoading(true);
    setError(null);
    const now = new Date();
    const start = new Date(now); start.setHours(0, 0, 0, 0);
    const end = new Date(now); end.setHours(23, 59, 59, 999);
    try {
      const db = supabase as any;
      const [todayResult, reviewResult, extraResult, appointmentResult, listResult] = await Promise.all([
        db.from(config.table).select('id', { count: 'exact', head: true }).gte('created_at', start.toISOString()).lte('created_at', end.toISOString()),
        db.from('specialist_review_sessions').select('id', { count: 'exact', head: true }).eq('specialty', config.reviewSpecialty).in('status', ['pending', 'scheduled', 'overdue']),
        config.extraTable === 'appointments'
          ? db.from('appointments').select('id', { count: 'exact', head: true }).ilike('department', '%' + config.departmentMatch + '%').gte('scheduled_at', now.toISOString())
          : config.extraTable === 'physio_treatment_plans'
            ? db.from('physio_treatment_plans').select('id', { count: 'exact', head: true }).eq('status', 'active')
            : config.extraTable === 'dietary_meal_orders'
              ? db.from('dietary_meal_orders').select('id', { count: 'exact', head: true }).eq('status', 'active')
              : config.extraTable === 'dental_assessments'
                ? db.from('dental_assessments').select('id', { count: 'exact', head: true })
                : Promise.resolve({ count: null, error: null }),
        db.from('appointments').select('id', { count: 'exact', head: true }).ilike('department', '%' + config.departmentMatch + '%').gte('scheduled_at', start.toISOString()).lte('scheduled_at', end.toISOString()).not('status', 'in', '("cancelled","no_show")'),
        db.from(config.table).select('id,patient_id,created_at,updated_at').order('created_at', { ascending: false }).limit(8)
      ]);
      const errors = [todayResult, reviewResult, extraResult, appointmentResult, listResult].filter(r => r?.error);
      if (errors.length) setError('Some dashboard data could not be loaded. Check role access and confirm the specialist migrations have been deployed.');
      setAssessmentsToday(todayResult.error ? null : (todayResult.count ?? 0));
      setPendingReviews(reviewResult.error ? null : (reviewResult.count ?? 0));
      setExtraCount(extraResult?.error ? null : (extraResult?.count ?? 0));
      setAppointmentsToday(appointmentResult.error ? null : (appointmentResult.count ?? 0));
      setItems(listResult.error || !Array.isArray(listResult.data) ? [] : listResult.data);
    } catch {
      setError('The specialist workspace is temporarily unavailable. Please retry.');
      setAssessmentsToday(null); setPendingReviews(null); setExtraCount(null); setAppointmentsToday(null); setItems([]);
    } finally {
      setLoading(false);
    }
  }, [user?.id, config]);

  useEffect(() => {
    void load();
  }, [load]);

  const metricCards = [
    { label: 'Today’s assessments', value: assessmentsToday, description: 'Specialty records created today', icon: ClipboardList, href: config.primaryHref },
    { label: 'Pending reviews', value: pendingReviews, description: 'Review sessions awaiting action', icon: Activity, href: '/appointments' },
    { label: 'Today’s clinics', value: appointmentsToday, description: 'Specialty appointments scheduled today', icon: CalendarDays, href: '/appointments' },
    { label: config.extraLabel ?? 'Active patients', value: extraCount, description: 'Current specialty workflow records', icon: Users, href: config.extraHref ?? '/patients' }
  ];

  return <div className="space-y-6 animate-fade-in">
    <section className="rounded-3xl border border-border bg-card p-5 shadow-sm sm:p-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">{config.eyebrow}</p>
          <h1 className="mt-1 text-2xl font-heading font-bold tracking-tight">{config.title}</h1>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">{config.description}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link to={config.primaryHref} className="btn-primary inline-flex items-center gap-2">{config.primaryLabel}<ArrowRight className="h-4 w-4" /></Link>
          <Link to="/appointments" className="btn-secondary inline-flex items-center gap-2"><CalendarDays className="h-4 w-4" />Appointments</Link>
          <RefreshButton onClick={() => void load()} loading={loading} label="Refresh specialist dashboard" />
        </div>
      </div>
    </section>
    {error && <div className="flex items-start gap-3 rounded-2xl border border-warning/30 bg-warning/5 p-4" role="status"><AlertTriangle className="mt-0.5 h-5 w-5 text-warning" /><div><p className="text-sm font-semibold">Partial workspace data</p><p className="mt-1 text-sm text-muted-foreground">{error}</p></div></div>}
    <section className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4" aria-label="Specialist key performance indicators">
      {metricCards.map(({ label, value, description, icon: Icon, href }) => <Link key={label} to={href} className="rounded-2xl border border-border bg-card p-4 transition-colors hover:border-primary/40 hover:shadow-sm">
        <div className="flex items-start justify-between gap-2"><p className="text-xs font-medium text-muted-foreground">{label}</p><Icon className="h-4 w-4 text-primary" /></div>
        <p className="mt-2 text-3xl font-bold tabular-nums">{loading ? '…' : value ?? '—'}</p>
        <p className="mt-1 text-[11px] text-muted-foreground">{description}</p>
      </Link>)}
    </section>
    <section className="grid grid-cols-1 gap-4 xl:grid-cols-[1.6fr_1fr]">
      <div className="overflow-hidden rounded-2xl border border-border bg-card">
        <div className="flex items-center justify-between border-b border-border p-4"><div><h2 className="font-semibold">Active list</h2><p className="mt-1 text-xs text-muted-foreground">Recent specialty records within your authorized facility</p></div><Link to="/patients" className="text-sm font-medium text-primary">Patient directory</Link></div>
        {items.length ? <div className="divide-y divide-border">{items.map(item => <div key={item.id} className="flex flex-wrap items-center justify-between gap-3 p-4">
          <div><p className="text-sm font-medium">Patient record · {item.patient_id.slice(0, 8).toUpperCase()}</p><p className="mt-1 text-xs text-muted-foreground">Updated {new Date(item.updated_at ?? item.created_at).toLocaleString()}</p></div>
          <span className="rounded-full border border-border px-2.5 py-1 text-xs text-muted-foreground">Assessment recorded</span>
        </div>)}</div> : <div className="p-8 text-center"><ClipboardList className="mx-auto h-7 w-7 text-muted-foreground" /><p className="mt-2 text-sm font-medium">{loading ? 'Loading active list…' : 'No specialty records found'}</p><p className="mt-1 text-xs text-muted-foreground">New records will appear here after an assessment is saved.</p></div>}
      </div>
      <div className="rounded-2xl border border-border bg-card p-4">
        <h2 className="font-semibold">Quick actions</h2><p className="mt-1 text-xs text-muted-foreground">Continue work in connected clinical modules</p>
        <div className="mt-4 space-y-2">
          <Link to={config.primaryHref} className="flex items-center justify-between rounded-xl border border-border p-3 text-sm transition-colors hover:border-primary/40"><span>{config.primaryLabel}</span><ArrowRight className="h-4 w-4 text-primary" /></Link>
          <Link to="/encounters" className="flex items-center justify-between rounded-xl border border-border p-3 text-sm transition-colors hover:border-primary/40"><span>Open encounters</span><ArrowRight className="h-4 w-4 text-primary" /></Link>
          <Link to="/appointments" className="flex items-center justify-between rounded-xl border border-border p-3 text-sm transition-colors hover:border-primary/40"><span>Schedule next session</span><ArrowRight className="h-4 w-4 text-primary" /></Link>
          <Link to={config.extraHref ?? '/patients'} className="flex items-center justify-between rounded-xl border border-border p-3 text-sm transition-colors hover:border-primary/40"><span>{config.extraLabel ?? 'Patient directory'}</span><ArrowRight className="h-4 w-4 text-primary" /></Link>
        </div>
      </div>
    </section>
  </div>;
}
