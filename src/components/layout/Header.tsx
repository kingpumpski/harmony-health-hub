import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Bell, Search, Settings, ChevronDown } from 'lucide-react';
import { cn } from '@/lib/utils';
import { UserRole } from '@/types';

const roleLabels: Record<UserRole, string> = {
  admin: 'Administrator',
  practitioner: 'Practitioner',
  nurse: 'Nurse',
  midwife: 'Midwife',
  lab_technician: 'Lab Technician',
  pharmacist: 'Pharmacist',
  accountant: 'Accountant',
  front_desk: 'Front Desk',
  canteen: 'Canteen Staff',
  patient: 'Patient',
};

export default function Header() {
  const { user, switchRole } = useAuth();
  const [showRoleSwitch, setShowRoleSwitch] = useState(false);
  const [showNotifications, setShowNotifications] = useState(false);

  if (!user) return null;

  const notifications = [
    { id: 1, title: 'Lab Results Ready', message: 'Patient John Doe - Blood test results available', time: '2m ago', priority: 'high' },
    { id: 2, title: 'Critical Vital Signs', message: 'Patient Mary Smith - BP 180/110', time: '5m ago', priority: 'critical' },
    { id: 3, title: 'New Appointment', message: 'Dr. Sarah Johnson scheduled for 2:30 PM', time: '15m ago', priority: 'normal' },
  ];

  return (
    <header className="sticky top-0 z-30 h-16 bg-card border-b border-border px-6 flex items-center justify-between">
      {/* Search */}
      <div className="flex-1 max-w-md">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search patients, appointments, records..."
            className="input-medical pl-10 w-full"
          />
        </div>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-4">
        {/* Demo Role Switcher */}
        <div className="relative">
          <button
            onClick={() => setShowRoleSwitch(!showRoleSwitch)}
            className="btn-ghost text-xs gap-1"
          >
            <span className="text-muted-foreground">Demo:</span>
            <span className="font-medium">{roleLabels[user.role]}</span>
            <ChevronDown className="w-3 h-3" />
          </button>
          
          {showRoleSwitch && (
            <div className="absolute right-0 mt-2 w-48 bg-card rounded-lg shadow-elevated border border-border py-2 animate-scale-in">
              {Object.entries(roleLabels).map(([role, label]) => (
                <button
                  key={role}
                  onClick={() => {
                    switchRole(role as UserRole);
                    setShowRoleSwitch(false);
                  }}
                  className={cn(
                    'w-full px-4 py-2 text-left text-sm hover:bg-muted transition-colors',
                    user.role === role && 'bg-primary/10 text-primary font-medium'
                  )}
                >
                  {label}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Notifications */}
        <div className="relative">
          <button
            onClick={() => setShowNotifications(!showNotifications)}
            className="relative p-2 rounded-lg hover:bg-muted transition-colors"
          >
            <Bell className="w-5 h-5 text-muted-foreground" />
            <span className="notification-dot" />
          </button>

          {showNotifications && (
            <div className="absolute right-0 mt-2 w-80 bg-card rounded-lg shadow-elevated border border-border animate-scale-in">
              <div className="p-4 border-b border-border">
                <h3 className="font-semibold">Notifications</h3>
              </div>
              <div className="max-h-80 overflow-y-auto">
                {notifications.map((notif) => (
                  <div
                    key={notif.id}
                    className={cn(
                      'p-4 border-b border-border last:border-0 hover:bg-muted/50 cursor-pointer transition-colors',
                      notif.priority === 'critical' && 'bg-critical/5 border-l-2 border-l-critical'
                    )}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <p className="font-medium text-sm">{notif.title}</p>
                        <p className="text-xs text-muted-foreground mt-1">{notif.message}</p>
                      </div>
                      <span className="text-xs text-muted-foreground whitespace-nowrap">{notif.time}</span>
                    </div>
                  </div>
                ))}
              </div>
              <div className="p-3 border-t border-border">
                <button className="btn-ghost text-sm w-full text-primary">
                  View All Notifications
                </button>
              </div>
            </div>
          )}
        </div>

        {/* Settings */}
        <button className="p-2 rounded-lg hover:bg-muted transition-colors">
          <Settings className="w-5 h-5 text-muted-foreground" />
        </button>
      </div>
    </header>
  );
}
