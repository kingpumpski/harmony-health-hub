import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Users, UserCog, Activity, Settings, Shield, Bell, TrendingUp, AlertTriangle, Server, Database } from 'lucide-react';
import StatCard from '@/components/ui/StatCard';
import { cn } from '@/lib/utils';

const systemStats = {
  activeUsers: 48,
  totalPatients: 12847,
  appointmentsToday: 156,
  systemUptime: '99.9%',
};

const recentActivity = [
  { id: 1, user: 'Dr. Sarah Johnson', action: 'Completed encounter for John Smith', time: '2 min ago', type: 'clinical' },
  { id: 2, user: 'Emily Williams (Nurse)', action: 'Recorded vitals for Bed W1-B02', time: '5 min ago', type: 'nursing' },
  { id: 3, user: 'David Brown (Pharmacy)', action: 'Dispensed prescription RX-2024-001', time: '8 min ago', type: 'pharmacy' },
  { id: 4, user: 'Lisa Anderson (Accounts)', action: 'Processed payment INV-2024-002', time: '12 min ago', type: 'billing' },
  { id: 5, user: 'System', action: 'Automated backup completed', time: '30 min ago', type: 'system' },
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
  { id: 1, type: 'warning', message: 'Database backup scheduled in 30 minutes', time: '10 min ago' },
  { id: 2, type: 'info', message: 'System update available (v2.4.1)', time: '2 hours ago' },
  { id: 3, type: 'success', message: 'All services running normally', time: '4 hours ago' },
];

export default function AdminDashboard() {
  const navigate = useNavigate();
  
  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Admin Dashboard</h1>
          <p className="text-muted-foreground">System Overview & Management</p>
        </div>
        <div className="flex gap-3">
          <button className="btn-secondary" onClick={() => navigate('/admin/logs')}>
            <Activity className="w-4 h-4" />
            System Logs
          </button>
          <button className="btn-primary" onClick={() => navigate('/admin/users')}>
            <UserCog className="w-4 h-4" />
            Manage Users
          </button>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Active Users"
          value={systemStats.activeUsers}
          change="Online now"
          changeType="positive"
          icon={Users}
          iconColor="text-success"
        />
        <StatCard
          title="Total Patients"
          value={systemStats.totalPatients.toLocaleString()}
          change="+124 this month"
          changeType="positive"
          icon={Database}
          iconColor="text-primary"
        />
        <StatCard
          title="Today's Appointments"
          value={systemStats.appointmentsToday}
          change="85% completion rate"
          changeType="positive"
          icon={TrendingUp}
          iconColor="text-info"
        />
        <StatCard
          title="System Uptime"
          value={systemStats.systemUptime}
          change="Last 30 days"
          changeType="positive"
          icon={Server}
          iconColor="text-success"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Recent Activity */}
        <div className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Recent System Activity</h2>
            <button className="btn-ghost text-sm" onClick={() => navigate('/admin/logs')}>View All Logs</button>
          </div>
          <div className="divide-y divide-border">
            {recentActivity.map((activity) => (
              <div key={activity.id} className="p-4 hover:bg-muted/30 transition-colors cursor-pointer" onClick={() => navigate('/admin/logs')}>
                <div className="flex items-start gap-3">
                  <div className={cn(
                    'w-2 h-2 rounded-full mt-2',
                    activity.type === 'clinical' && 'bg-primary',
                    activity.type === 'nursing' && 'bg-success',
                    activity.type === 'pharmacy' && 'bg-accent',
                    activity.type === 'billing' && 'bg-info',
                    activity.type === 'system' && 'bg-muted-foreground'
                  )} />
                  <div className="flex-1">
                    <p className="font-medium text-sm">{activity.user}</p>
                    <p className="text-sm text-muted-foreground">{activity.action}</p>
                  </div>
                  <span className="text-xs text-muted-foreground">{activity.time}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Users by Role */}
        <div className="card-medical">
          <div className="p-5 border-b border-border">
            <h2 className="font-semibold">Staff by Department</h2>
          </div>
          <div className="p-5 space-y-4">
            {usersByRole.map((item) => (
              <div key={item.role} className="cursor-pointer hover:opacity-80 transition-opacity" onClick={() => navigate('/admin/users')}>
                <div className="flex items-center justify-between mb-1">
                  <span className="text-sm">{item.role}</span>
                  <span className="text-sm font-semibold">{item.count}</span>
                </div>
                <div className="h-2 bg-muted rounded-full overflow-hidden">
                  <div
                    className={cn('h-full rounded-full', item.color)}
                    style={{ width: `${(item.count / 50) * 100}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-ghost text-sm text-primary w-full" onClick={() => navigate('/admin/users')}>
              <UserCog className="w-4 h-4" />
              Manage Staff
            </button>
          </div>
        </div>
      </div>

      {/* System Alerts & Quick Actions */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* System Alerts */}
        <div className="card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">System Alerts</h2>
            <span className="badge-info">{systemAlerts.length} alerts</span>
          </div>
          <div className="divide-y divide-border">
            {systemAlerts.map((alert) => (
              <div key={alert.id} className="p-4 flex items-start gap-3 cursor-pointer hover:bg-muted/30 transition-colors" onClick={() => navigate('/notifications')}>
                <div className={cn(
                  'p-2 rounded-lg',
                  alert.type === 'warning' && 'bg-warning/10',
                  alert.type === 'info' && 'bg-info/10',
                  alert.type === 'success' && 'bg-success/10'
                )}>
                  {alert.type === 'warning' && <AlertTriangle className="w-4 h-4 text-warning" />}
                  {alert.type === 'info' && <Bell className="w-4 h-4 text-info" />}
                  {alert.type === 'success' && <Shield className="w-4 h-4 text-success" />}
                </div>
                <div className="flex-1">
                  <p className="text-sm">{alert.message}</p>
                  <p className="text-xs text-muted-foreground mt-1">{alert.time}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Quick Actions */}
        <div className="card-medical p-5">
          <h2 className="font-semibold mb-4">Admin Quick Actions</h2>
          <div className="grid grid-cols-2 gap-3">
            {[
              { label: 'User Management', icon: UserCog, color: 'bg-primary', href: '/admin/users' },
              { label: 'Role Permissions', icon: Shield, color: 'bg-success', href: '/admin/roles' },
              { label: 'System Settings', icon: Settings, color: 'bg-info', href: '/admin/settings' },
              { label: 'Audit Logs', icon: Activity, color: 'bg-warning', href: '/admin/logs' },
              { label: 'Notifications', icon: Bell, color: 'bg-accent', href: '/notifications' },
              { label: 'Database', icon: Database, color: 'bg-fertility', href: '/admin/system' },
            ].map((action) => (
              <button
                key={action.label}
                onClick={() => navigate(action.href)}
                className="flex items-center gap-3 p-4 rounded-lg border border-border hover:bg-muted/50 transition-all"
              >
                <div className={cn('w-10 h-10 rounded-lg flex items-center justify-center text-white', action.color)}>
                  <action.icon className="w-5 h-5" />
                </div>
                <span className="text-sm font-medium">{action.label}</span>
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
