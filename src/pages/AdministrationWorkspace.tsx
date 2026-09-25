import { Link } from 'react-router-dom';
import { Bell, Database, FileClock, Settings, ShieldCheck, Upload, Users } from 'lucide-react';

const items = [
  { label: 'User Management', href: '/admin/users', icon: Users, description: 'Onboard users, assign roles and manage staff access.' },
  { label: 'Roles & Permissions', href: '/admin/permissions', icon: ShieldCheck, description: 'Configure role permissions without changing application code.' },
  { label: 'Facility Settings', href: '/admin/settings', icon: Settings, description: 'Configure facility workflows, including emergency treatment and financial overrides.' },
  { label: 'Notifications', href: '/notifications', icon: Bell, description: 'Review alerts, notification history and actionable clinical or operational messages.' },
  { label: 'Notification Delivery', href: '/admin/settings', icon: Bell, description: 'Configure facility email, SMS, WhatsApp and other delivery providers from secure settings.' },
  { label: 'System Library', href: '/admin/system', icon: Database, description: 'Maintain shared system configuration and reference data.' },
  { label: 'Audit Logs', href: '/admin/logs', icon: FileClock, description: 'Review administrative and operational audit activity.' },
  { label: 'Data Import & Sync', href: '/admin/data-import', icon: Upload, description: 'Controlled imports and offline synchronization administration.' },
];

export default function AdministrationWorkspace() {
  return <div className="space-y-6 animate-fade-in"><header><div className="flex items-center gap-3"><Settings className="h-7 w-7 text-primary" /><div><h1 className="text-2xl font-heading font-bold">Administration</h1><p className="text-sm text-muted-foreground">System configuration, onboarding, permissions, auditability and operational controls.</p></div></div></header><div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">{items.map(item => { const Icon=item.icon; return <Link key={item.href} to={item.href} className="card-medical p-5 transition-transform hover:-translate-y-0.5"><Icon className="h-5 w-5 text-primary" /><h2 className="mt-4 font-semibold">{item.label}</h2><p className="mt-1 text-sm text-muted-foreground">{item.description}</p></Link>; })}</div></div>;
}
