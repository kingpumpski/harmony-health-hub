import { useMemo, type ReactNode } from 'react';
import { Activity, AlertTriangle, BedDouble, CalendarDays, ClipboardList, FlaskConical, Pill, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import DashboardLayout, { type DashboardKpi } from '@/components/layouts/DashboardLayout';
import RouteLoadingScreen from '@/components/system/RouteLoadingScreen';
import { useRoleDashboardData, type DashboardRole } from '@/hooks/useRoleDashboardData';

type Props = {
  role: DashboardRole;
  title: string;
  subtitle: string;
  actions: Array<{ label: string; href: string; icon: typeof Activity }>;
};

const displayTime = (value?: string) => {
  if (!value) return '';
  const elapsed = Math.max(0, Date.now() - Date.parse(value));
  const minutes = Math.floor(elapsed / 60000);
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hr ago`;
  return `${Math.floor(hours / 24)} days ago`;
};

const iconFor = (label: string) => {
  if (/appointment|schedule/i.test(label)) return CalendarDays;
  if (/lab|test|result|turnaround/i.test(label)) return FlaskConical;
  if (/inpatient|bed|ward/i.test(label)) return BedDouble;
  if (/prescription|dispens|pharmacy|stock|medication/i.test(label)) return Pill;
  if (/triage|patient|nurse/i.test(label)) return Users;
  return Activity;
};

function Panel({ title, children }: { title: string; children: ReactNode }) {
  return <section className="rounded-xl border border-border bg-white p-4 shadow-sm">
    <h2 className="text-sm font-semibold">{title}</h2>
    <div className="mt-3">{children}</div>
  </section>;
}

export default function RoleOperationalDashboard({ role, title, subtitle, actions }: Props) {
  const { user } = useAuth();
  const query = useRoleDashboardData(role, user?.id);

  const topKpis = useMemo<DashboardKpi[]>(() => (query.data?.topMetrics ?? []).map((metric) => ({
    ...metric,
    icon: iconFor(metric.label),
  })), [query.data?.topMetrics]);
  const secondaryKpis = useMemo<DashboardKpi[]>(() => (query.data?.secondaryMetrics ?? []).map((metric) => ({
    ...metric,
    icon: iconFor(metric.label),
  })), [query.data?.secondaryMetrics]);

  if (query.isLoading) return <RouteLoadingScreen />;

  if (query.isError) {
    return <div role="alert" className="rounded-xl border border-critical/30 bg-critical/5 p-5">
      <h1 className="font-semibold text-critical">{title} data unavailable</h1>
      <p className="mt-1 text-sm text-muted-foreground">{query.error.message}</p>
      <button type="button" onClick={() => void query.refetch()} className="btn-secondary mt-3">Retry</button>
    </div>;
  }

  const data = query.data;
  const activityPanel = <Panel title={`Recent ${role === 'lab_technician' ? 'Lab' : role === 'pharmacist' ? 'Pharmacy' : role === 'accountant' ? 'Billing' : role === 'nurse' ? 'Nursing' : 'Clinical'} Activity`}>
    {data.activities.length ? <ul className="divide-y divide-border">
      {data.activities.map((activity) => <li key={activity.id} className="py-3 first:pt-0 last:pb-0">
        {activity.href ? <Link to={activity.href} className="font-medium hover:text-primary">{activity.title}</Link> : <p className="font-medium">{activity.title}</p>}
        {activity.detail && <p className="mt-0.5 text-xs text-muted-foreground">{activity.detail}</p>}
        {activity.createdAt && <p className="mt-1 text-[11px] text-muted-foreground">{displayTime(activity.createdAt)}</p>}
      </li>)}
    </ul> : <p className="text-sm text-muted-foreground">No recent activity to show.</p>}
  </Panel>;
  const actionPanel = <Panel title="Quick Actions">
    <div className="grid gap-2">
      {actions.map(({ label, href, icon: Icon }) => <Link key={href} to={href} className="btn-secondary inline-flex items-center justify-start gap-2">
        <Icon className="h-4 w-4" aria-hidden="true" />{label}
      </Link>)}
    </div>
  </Panel>;
  const schedulePanel = data.upcoming.length > 0 ? <Panel title="My Schedule">
    <ul className="space-y-3">
      {data.upcoming.map((item) => <li key={item.id}>
        <Link to={item.href ?? '/appointments'} className="text-sm font-medium hover:text-primary">{item.title}</Link>
        {item.detail && <p className="text-xs text-muted-foreground">{item.detail}</p>}
      </li>)}
    </ul>
  </Panel> : null;
  const bottom = data.alerts.length > 0 ? <div className="grid gap-3 sm:grid-cols-2">
    {data.alerts.map((alert) => <Link key={alert.id} to={alert.href ?? '/notifications'} className={`flex items-start gap-3 rounded-xl border p-4 shadow-sm ${alert.severity === 'critical' ? 'border-critical/30 bg-critical/5' : 'border-warning/30 bg-warning/5'}`}>
      <AlertTriangle className={`mt-0.5 h-4 w-4 shrink-0 ${alert.severity === 'critical' ? 'text-critical' : 'text-warning'}`} aria-hidden="true" />
      <span><span className="block text-sm font-semibold">{alert.title}</span>{alert.detail && <span className="mt-1 block text-xs text-muted-foreground">{alert.detail}</span>}</span>
    </Link>)}
  </div> : <Panel title="System Alerts"><p className="text-sm text-muted-foreground">No active alerts.</p></Panel>;

  return <DashboardLayout
    headerTitle={title}
    headerSubtitle={subtitle}
    kpiCards={topKpis}
    secondaryKpiCards={secondaryKpis}
    mainContent={activityPanel}
    sideContent={<>{actionPanel}{schedulePanel}</>}
    bottomContent={bottom}
  />;
}
