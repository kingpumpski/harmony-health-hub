import { Link } from 'react-router-dom';
import { FileSearch, History, Bell, ShieldCheck } from 'lucide-react';

const tools = [
  { label: 'System Logs', href: '/admin/logs', icon: FileSearch, description: 'Review operational audit events and troubleshoot failures in real time.' },
  { label: 'Offline Synchronization', href: '/admin/offline-sync', icon: History, description: 'Inspect queued device changes and release failed synchronization attempts.' },
  { label: 'Notifications', href: '/notifications', icon: Bell, description: 'Monitor application notifications and operational alerts.' },
];

export default function ITSupportWorkspace() {
  return (
    <div className="space-y-6 animate-fade-in">
      <header>
        <div className="flex items-center gap-3">
          <ShieldCheck className="h-7 w-7 text-primary" />
          <div>
            <h1 className="text-2xl font-heading font-bold">IT Support</h1>
            <p className="text-sm text-muted-foreground">Real-time application troubleshooting, audit visibility and offline synchronization support without granting clinical or financial authority.</p>
          </div>
        </div>
      </header>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {tools.map((item) => {
          const Icon = item.icon;
          return <Link key={item.href} to={item.href} className="card-medical p-5 transition-transform hover:-translate-y-0.5">
            <Icon className="h-5 w-5 text-primary" />
            <h2 className="mt-4 font-semibold">{item.label}</h2>
            <p className="mt-1 text-sm text-muted-foreground">{item.description}</p>
          </Link>;
        })}
      </div>
      <div className="rounded-xl border bg-muted/30 p-4 text-sm text-muted-foreground">
        IT Admin access is intentionally scoped to support operations. Patient care, billing approval, role administration and clinical decision workflows remain controlled by their existing roles and server-side authorization.
      </div>
    </div>
  );
}
