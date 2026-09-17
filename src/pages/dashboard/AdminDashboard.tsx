import { Link } from 'react-router-dom';
import { Users, UserCog, Activity, Settings, Shield, Bell, TrendingUp, AlertTriangle, Server, Database, ClipboardList, Cloud, Upload } from 'lucide-react';
import StatCard from '@/components/ui/StatCard';
import { cn } from '@/lib/utils';

const systemStats = {
  activeUsers: 48,
  totalPatients: 12847,
  appointmentsToday: 156,
  systemUptime: '99.9%',
};

const recentActivity = [
  { id: 1, user: 'Clinical team', action: 'Recent encounter activity available in System Logs', time: 'Live', type: 'clinical' },
  { id: 2, user: 'Nursing team', action: 'Ward and handover activity available in Clinical Operations', time: 'Live', type: 'nursing' },
  { id: 3, user: 'Pharmacy', action: 'Dispensing and medication activity available in Pharmacy', time: 'Live', type: 'pharmacy' },
  { id: 4, user: 'Accounts', action: 'Billing and claims activity available in Accounts Approvals', time: 'Live', type: 'billing' },
  { id: 5, user: 'System', action: 'Offline synchronization and operational health are available in Administration', time: 'Live', type: 'system' },
];

const usersByRole = [
  { role: 'Practitioners', count: 24, color: 'bg-primary' },
  { role: 'Nurses', count: 42, color: 'bg-success' },
  { role: 'Lab Technicians', count: 8, color: 'bg-warning' },
  { role: 'Pharmacists', count: 6, color: 'bg-accent' },
  { role: 'Accountants', count: 4, color: 'bg-info' },
  { role: 'Front Desk', count: 12, color: 'bg-fertility' },
];

const systemAlerts = [
  { id: 1, type: 'warning', message: 'Review scheduled maintenance and operational alerts in System Logs.', time: 'Operational' },
  { id: 2, type: 'info', message: 'Use Offline Synchronization to review queued work and reconciliation state.', time: 'Operational' },
  { id: 3, type: 'success', message: 'Core administration controls are available from this workspace.', time: 'Operational' },
];

export default function AdminDashboard() {
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-primary">Harmony Health Hub</p>
          <h1 className="text-2xl font-heading font-bold">Administration Command Center</h1>
          <p className="text-muted-foreground">System governance, staff access, operational health and clinical-service oversight.</p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Link to="/admin/logs" className="btn-secondary"><Activity className="w-4 h-4" />System Logs</Link>
          <Link to="/admin/users" className="btn-primary"><UserCog className="w-4 h-4" />Manage Users</Link>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard title="Active Users" value={systemStats.activeUsers} change="Online now" changeType="positive" icon={Users} iconColor="text-success" />
        <StatCard title="Total Patients" value={systemStats.totalPatients.toLocaleString()} change="Registered records" changeType="positive" icon={Database} iconColor="text-primary" />
        <StatCard title="Today's Appointments" value={systemStats.appointmentsToday} change="Operational queue" changeType="neutral" icon={TrendingUp} iconColor="text-info" />
        <StatCard title="System Uptime" value={systemStats.systemUptime} change="Last 30 days" changeType="positive" icon={Server} iconColor="text-success" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 card-medical overflow-hidden">
          <div className="p-5 border-b border-border flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div><h2 className="font-semibold">Operational Activity</h2><p className="text-xs text-muted-foreground mt-1">Use the linked modules for authoritative records rather than dashboard-only summaries.</p></div>
            <Link to="/admin/logs" className="btn-ghost text-sm">Open Audit Logs</Link>
          </div>
          <div className="divide-y divide-border">
            {recentActivity.map((activity) => (
              <div key={activity.id} className="p-4 hover:bg-muted/30 transition-colors">
                <div className="flex items-start gap-3">
                  <div className={cn('w-2 h-2 rounded-full mt-2 shrink-0', activity.type === 'clinical' && 'bg-primary', activity.type === 'nursing' && 'bg-success', activity.type === 'pharmacy' && 'bg-accent', activity.type === 'billing' && 'bg-info', activity.type === 'system' && 'bg-muted-foreground')} />
                  <div className="flex-1 min-w-0"><p className="font-medium text-sm">{activity.user}</p><p className="text-sm text-muted-foreground">{activity.action}</p></div>
                  <span className="text-xs text-muted-foreground shrink-0">{activity.time}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="card-medical">
          <div className="p-5 border-b border-border"><h2 className="font-semibold">Staff by Department</h2><p className="text-xs text-muted-foreground mt-1">Administrative snapshot</p></div>
          <div className="p-5 space-y-4">
            {usersByRole.map((item) => <div key={item.role}><div className="flex items-center justify-between mb-1"><span className="text-sm">{item.role}</span><span className="text-sm font-semibold">{item.count}</span></div><div className="h-2 bg-muted rounded-full overflow-hidden"><div className={cn('h-full rounded-full', item.color)} style={{ width: `${Math.min((item.count / 50) * 100, 100)}%` }} /></div></div>)}
          </div>
          <div className="p-4 border-t border-border"><Link to="/admin/users" className="btn-ghost text-sm text-primary w-full"><UserCog className="w-4 h-4" />Manage Staff</Link></div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="card-medical overflow-hidden">
          <div className="p-5 border-b border-border flex items-center justify-between"><div><h2 className="font-semibold">System Alerts</h2><p className="text-xs text-muted-foreground mt-1">Administration follow-up</p></div><span className="badge-info">{systemAlerts.length} items</span></div>
          <div className="divide-y divide-border">{systemAlerts.map((alert) => <div key={alert.id} className="p-4 flex items-start gap-3"><div className={cn('p-2 rounded-lg', alert.type === 'warning' && 'bg-warning/10', alert.type === 'info' && 'bg-info/10', alert.type === 'success' && 'bg-success/10')}>{alert.type === 'warning' && <AlertTriangle className="w-4 h-4 text-warning" />}{alert.type === 'info' && <Bell className="w-4 h-4 text-info" />}{alert.type === 'success' && <Shield className="w-4 h-4 text-success" />}</div><div className="flex-1"><p className="text-sm">{alert.message}</p><p className="text-xs text-muted-foreground mt-1">{alert.time}</p></div></div>)}</div>
        </div>

        <div className="card-medical p-5">
          <h2 className="font-semibold mb-1">Admin Quick Actions</h2><p className="text-sm text-muted-foreground mb-4">Jump directly to the workflows used to operate the facility.</p>
          <div className="grid grid-cols-2 gap-3">
            {[
              { label: 'User Management', icon: UserCog, href: '/admin/users', color: 'bg-primary' },
              { label: 'Role Permissions', icon: Shield, href: '/admin/roles', color: 'bg-success' },
              { label: 'System Settings', icon: Settings, href: '/admin/settings', color: 'bg-info' },
              { label: 'Audit Logs', icon: Activity, href: '/admin/logs', color: 'bg-warning' },
              { label: 'Notifications', icon: Bell, href: '/notifications', color: 'bg-accent' },
              { label: 'Offline Sync', icon: Cloud, href: '/admin/offline-sync', color: 'bg-fertility' },
              { label: 'Data Import', icon: Upload, href: '/admin/data-import', color: 'bg-primary' },
              { label: 'Reports', icon: ClipboardList, href: '/reports', color: 'bg-info' },
            ].map((action) => <Link key={action.label} to={action.href} className="flex items-center gap-3 p-3 rounded-xl border border-border hover:bg-muted/50 hover:border-primary/40 transition-all"><div className={cn('w-9 h-9 rounded-lg flex items-center justify-center text-white shrink-0', action.color)}><action.icon className="w-4 h-4" /></div><span className="text-sm font-medium">{action.label}</span></Link>)}
          </div>
        </div>
      </div>
    </div>
  );
}
