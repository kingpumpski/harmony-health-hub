import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Users, Calendar, Clock, UserPlus, Search, Filter, Plus } from 'lucide-react';
import StatCard from '@/components/ui/StatCard';
import AlertBanner from '@/components/ui/AlertBanner';
import { cn } from '@/lib/utils';

const todayAppointments = [
  { id: 1, time: '09:00 AM', patient: 'John Smith', doctor: 'Dr. Sarah Johnson', type: 'Consultation', status: 'checked-in' },
  { id: 2, time: '09:30 AM', patient: 'Mary Williams', doctor: 'Dr. Michael Chen', type: 'Follow-up', status: 'scheduled' },
  { id: 3, time: '10:00 AM', patient: 'Robert Brown', doctor: 'Dr. Emily Davis', type: 'Lab Results', status: 'scheduled' },
  { id: 4, time: '10:30 AM', patient: 'Jennifer Wilson', doctor: 'Dr. Sarah Johnson', type: 'Consultation', status: 'scheduled' },
  { id: 5, time: '11:00 AM', patient: 'David Miller', doctor: 'Dr. James Taylor', type: 'Procedure', status: 'scheduled' },
];

const recentRegistrations = [
  { id: 1, name: 'Alice Thompson', time: '8:45 AM', type: 'New Patient', insurance: 'Yes' },
  { id: 2, name: 'George Martinez', time: '8:30 AM', type: 'Returning', insurance: 'No' },
  { id: 3, name: 'Susan Anderson', time: '8:15 AM', type: 'New Patient', insurance: 'Yes' },
];

export default function FrontDeskDashboard() {
  const navigate = useNavigate();
  const [showCriticalAlert, setShowCriticalAlert] = useState(true);

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Front Desk Dashboard</h1>
          <p className="text-muted-foreground">Manage patient registration and appointments</p>
        </div>
        <div className="flex gap-3">
          <button className="btn-secondary" onClick={() => navigate('/appointments')}>
            <Calendar className="w-4 h-4" />
            Schedule
          </button>
          <button className="btn-primary" onClick={() => navigate('/registration')}>
            <UserPlus className="w-4 h-4" />
            Register Patient
          </button>
        </div>
      </div>

      {/* Critical Alert */}
      {showCriticalAlert && (
        <AlertBanner
          type="warning"
          title="High Patient Volume"
          message="Expected 15% higher patient volume today. Consider opening additional registration counters."
          onDismiss={() => setShowCriticalAlert(false)}
        />
      )}

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Today's Appointments"
          value={42}
          change="+8 from yesterday"
          changeType="positive"
          icon={Calendar}
          iconColor="text-primary"
        />
        <StatCard
          title="Checked In"
          value={18}
          change="43% of scheduled"
          changeType="neutral"
          icon={Users}
          iconColor="text-success"
        />
        <StatCard
          title="Waiting"
          value={7}
          change="Avg. 12 min wait"
          changeType="neutral"
          icon={Clock}
          iconColor="text-warning"
        />
        <StatCard
          title="New Registrations"
          value={12}
          change="+3 from yesterday"
          changeType="positive"
          icon={UserPlus}
          iconColor="text-info"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Today's Appointments */}
        <div className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Today's Appointments</h2>
            <div className="flex items-center gap-2">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <input
                  type="text"
                  placeholder="Search..."
                  className="input-medical pl-9 py-1.5 text-sm w-48"
                />
              </div>
              <button className="btn-ghost p-2">
                <Filter className="w-4 h-4" />
              </button>
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="table-medical">
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Patient</th>
                  <th>Doctor</th>
                  <th>Type</th>
                  <th>Status</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {todayAppointments.map((apt) => (
                  <tr key={apt.id}>
                    <td className="font-medium">{apt.time}</td>
                    <td>{apt.patient}</td>
                    <td className="text-muted-foreground">{apt.doctor}</td>
                    <td>{apt.type}</td>
                    <td>
                      <span
                        className={cn(
                          'badge-status',
                          apt.status === 'checked-in' && 'badge-success',
                          apt.status === 'scheduled' && 'badge-info'
                        )}
                      >
                        {apt.status === 'checked-in' ? 'Checked In' : 'Scheduled'}
                      </span>
                    </td>
                    <td>
                      <button className="btn-ghost text-xs py-1 px-2" onClick={() => navigate('/appointments')}>
                        {apt.status === 'scheduled' ? 'Check In' : 'View'}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-ghost text-sm text-primary" onClick={() => navigate('/appointments')}>View All Appointments →</button>
          </div>
        </div>

        {/* Recent Registrations */}
        <div className="card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Recent Registrations</h2>
            <button className="btn-ghost p-1.5" onClick={() => navigate('/registration')}>
              <Plus className="w-4 h-4" />
            </button>
          </div>
          <div className="divide-y divide-border">
            {recentRegistrations.map((reg) => (
              <div key={reg.id} className="p-4 hover:bg-muted/30 transition-colors cursor-pointer" onClick={() => navigate('/patients')}>
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-medium">{reg.name}</p>
                    <p className="text-sm text-muted-foreground mt-0.5">{reg.time}</p>
                  </div>
                  <div className="text-right">
                    <span className={cn(
                      'badge-status',
                      reg.type === 'New Patient' ? 'badge-info' : 'badge-success'
                    )}>
                      {reg.type}
                    </span>
                    {reg.insurance === 'Yes' && (
                      <p className="text-xs text-success mt-1">Insured</p>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-ghost text-sm text-primary w-full" onClick={() => navigate('/patients')}>View All →</button>
          </div>
        </div>
      </div>

      {/* Quick Actions */}
      <div className="card-medical p-5">
        <h2 className="font-semibold mb-4">Quick Actions</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {[
            { label: 'New Registration', icon: UserPlus, color: 'bg-primary', href: '/registration' },
            { label: 'Schedule Appointment', icon: Calendar, color: 'bg-info', href: '/appointments' },
            { label: 'Patient Lookup', icon: Search, color: 'bg-success', href: '/patients' },
            { label: 'Print Queue Ticket', icon: Clock, color: 'bg-warning', href: '/vitals' },
          ].map((action) => (
            <button
              key={action.label}
              onClick={() => navigate(action.href)}
              className="flex flex-col items-center gap-3 p-4 rounded-lg border border-border hover:bg-muted/50 transition-all hover:scale-[1.02]"
            >
              <div className={cn('w-12 h-12 rounded-xl flex items-center justify-center text-white', action.color)}>
                <action.icon className="w-6 h-6" />
              </div>
              <span className="text-sm font-medium">{action.label}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
