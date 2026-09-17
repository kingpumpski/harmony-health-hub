import { Link } from 'react-router-dom';
import { Activity, Bell, Cloud, Database, FileText, Settings, Shield, Upload, UserCog } from 'lucide-react';
import FinancialSettlementCard from '@/components/FinancialSettlementCard';

/**
 * Administration role surface.
 *
 * Operational counters and alerts are owned by the shared live WorkflowSummary
 * and domain dashboards. This surface intentionally avoids fabricated user,
 * patient, uptime and staffing figures.
 */
export default function AdminDashboard() {
  const actions = [
    { label: 'User Management', icon: UserCog, href: '/admin/users', description: 'Manage staff accounts and access.' },
    { label: 'Role Permissions', icon: Shield, href: '/admin/roles', description: 'Review role-based permissions.' },
    { label: 'System Settings', icon: Settings, href: '/admin/settings', description: 'Configure facility workflow rules.' },
    { label: 'Audit Logs', icon: Activity, href: '/admin/logs', description: 'Review authoritative system activity.' },
    { label: 'Notifications', icon: Bell, href: '/notifications', description: 'Review operational notifications.' },
    { label: 'Offline Sync', icon: Cloud, href: '/admin/offline-sync', description: 'Review queued and reconciled work.' },
    { label: 'Data Import', icon: Upload, href: '/admin/data-import', description: 'Use the controlled data import workflow.' },
    { label: 'Reports', icon: FileText, href: '/reports', description: 'Open the reporting workspace.' },
  ];

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-primary">Harmony Health Hub</p>
          <h1 className="text-2xl font-heading font-bold">Administration Command Center</h1>
          <p className="text-muted-foreground">System governance, access control, workflow configuration and operational oversight.</p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Link to="/admin/logs" className="btn-secondary"><Activity className="w-4 h-4" />System Logs</Link>
          <Link to="/admin/users" className="btn-primary"><UserCog className="w-4 h-4" />Manage Users</Link>
        </div>
      </div>

      <section className="card-medical p-5">
        <div className="flex items-start gap-3">
          <Database className="w-5 h-5 text-primary mt-0.5" />
          <div>
            <h2 className="font-semibold">Live operational control</h2>
            <p className="text-sm text-muted-foreground mt-1">
              Queue counters, clinical alerts, service waiting states and financial workflow notifications are supplied by the shared live dashboard layer. This role surface does not maintain a second copy of those records.
            </p>
          </div>
        </div>
      </section>

      <FinancialSettlementCard />

      <section className="card-medical p-5">
        <div className="mb-4">
          <h2 className="font-semibold">Administration Workspaces</h2>
          <p className="text-sm text-muted-foreground mt-1">Open the authoritative workflow instead of relying on dashboard-only summaries.</p>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          {actions.map(({ label, icon: Icon, href, description }) => (
            <Link key={href} to={href} className="card-medical p-4 hover:border-primary/40 hover:-translate-y-0.5 transition-all">
              <Icon className="w-5 h-5 text-primary mb-3" />
              <p className="font-semibold text-sm">{label}</p>
              <p className="text-xs text-muted-foreground mt-1">{description}</p>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
