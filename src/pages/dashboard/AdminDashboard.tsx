import { Activity, Bell, Database, Settings, Shield, Upload, UserCog } from 'lucide-react';
import { Link } from 'react-router-dom';

export default function AdminDashboard() {
  const actions = [
    { label: 'User Management', icon: UserCog, href: '/admin/users', description: 'Manage staff accounts and access.' },
    { label: 'Role Permissions', icon: Shield, href: '/admin/roles', description: 'Review role-based permissions.' },
    { label: 'System Settings', icon: Settings, href: '/admin/settings', description: 'Configure facility workflow rules.' },
    { label: 'Audit Logs', icon: Activity, href: '/admin/logs', description: 'Review authoritative system activity.' },
    { label: 'Data Import', icon: Upload, href: '/admin/data-import', description: 'Use the controlled data import workflow.' },
  ];

  return (
    <div className="space-y-5 animate-fade-in">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-primary">Administration</p>
          <h1 className="mt-1 text-2xl font-heading font-bold">Facility Administration</h1>
          <p className="mt-1 text-sm text-muted-foreground">Access, configuration and operational oversight.</p>
        </div>
        <Link to="/admin/users" className="btn-primary inline-flex items-center gap-2"><UserCog className="h-4 w-4" /> Manage Users</Link>
      </header>
      <section className="card-medical p-4">
        <div className="flex items-center gap-3">
          <Database className="h-5 w-5 text-primary" />
          <div><p className="font-semibold text-sm">Operational administration</p><p className="text-xs text-muted-foreground mt-0.5">Open the authoritative workspace for each administrative task.</p></div>
        </div>
      </section>
      <section className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {actions.map(({ label, icon: Icon, href, description }) => (
          <Link key={href} to={href} className="card-medical p-4 hover:border-primary/40 transition-colors">
            <Icon className="h-5 w-5 text-primary mb-3" />
            <p className="font-semibold text-sm">{label}</p>
            <p className="text-xs text-muted-foreground mt-1">{description}</p>
          </Link>
        ))}
      </section>
    </div>
  );
}
