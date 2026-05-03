import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Users, Calendar, FileText, FlaskConical, AlertTriangle, Clock, Stethoscope, TrendingUp } from 'lucide-react';
import StatCard from '@/components/ui/StatCard';
import AlertBanner from '@/components/ui/AlertBanner';
import { cn } from '@/lib/utils';

const upcomingPatients = [
  { id: 1, time: '10:00 AM', name: 'John Smith', age: 45, reason: 'Chest pain follow-up', hasLabResults: true, status: 'waiting' },
  { id: 2, time: '10:30 AM', name: 'Mary Williams', age: 32, reason: 'Annual checkup', hasLabResults: false, status: 'scheduled' },
  { id: 3, time: '11:00 AM', name: 'Robert Brown', age: 58, reason: 'Diabetes management', hasLabResults: true, status: 'scheduled' },
  { id: 4, time: '11:30 AM', name: 'Sarah Davis', age: 28, reason: 'Fertility consultation', hasLabResults: false, status: 'scheduled' },
];

const pendingLabResults = [
  { id: 1, patient: 'Alice Thompson', test: 'Complete Blood Count', priority: 'routine', submitted: '2 hours ago' },
  { id: 2, patient: 'George Martinez', test: 'Liver Function Panel', priority: 'urgent', submitted: '1 hour ago' },
  { id: 3, patient: 'Susan Anderson', test: 'Thyroid Panel', priority: 'routine', submitted: '3 hours ago' },
];

const criticalAlerts = [
  { id: 1, patient: 'James Wilson', type: 'High BP', value: '185/120 mmHg', time: '5 min ago' },
  { id: 2, patient: 'Emma Taylor', type: 'High Temp', value: '39.8°C', time: '12 min ago' },
];

export default function PractitionerDashboard() {
  const navigate = useNavigate();
  const [selectedPatient, setSelectedPatient] = useState<number | null>(null);

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Clinical Dashboard</h1>
          <p className="text-muted-foreground">Dr. Sarah Johnson • Internal Medicine</p>
        </div>
        <div className="flex gap-3">
          <button className="btn-secondary" onClick={() => navigate('/appointments')}>
            <Calendar className="w-4 h-4" />
            My Schedule
          </button>
          <button className="btn-primary" onClick={() => navigate('/encounters')}>
            <Stethoscope className="w-4 h-4" />
            Start Encounter
          </button>
        </div>
      </div>

      {/* Critical Alerts */}
      {criticalAlerts.length > 0 && (
        <div className="space-y-3">
          {criticalAlerts.map((alert) => (
            <AlertBanner
              key={alert.id}
              type="critical"
              title={`Critical: ${alert.type} - ${alert.patient}`}
              message={`Reading: ${alert.value} • Recorded ${alert.time}. Immediate attention required.`}
            />
          ))}
        </div>
      )}

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Today's Patients"
          value={16}
          change="4 remaining"
          changeType="neutral"
          icon={Users}
          iconColor="text-primary"
        />
        <StatCard
          title="Pending Lab Results"
          value={8}
          change="2 urgent"
          changeType="negative"
          icon={FlaskConical}
          iconColor="text-warning"
        />
        <StatCard
          title="Encounters Today"
          value={12}
          change="75% completion"
          changeType="positive"
          icon={FileText}
          iconColor="text-success"
        />
        <StatCard
          title="Avg. Consultation"
          value="18m"
          change="On schedule"
          changeType="positive"
          icon={Clock}
          iconColor="text-info"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Patient Queue */}
        <div className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border">
            <h2 className="font-semibold">Upcoming Patients</h2>
          </div>
          <div className="divide-y divide-border">
            {upcomingPatients.map((patient) => (
              <div
                key={patient.id}
                className={cn(
                  'p-4 cursor-pointer transition-all',
                  selectedPatient === patient.id ? 'bg-primary/5 border-l-2 border-l-primary' : 'hover:bg-muted/30'
                )}
                onClick={() => {
                  setSelectedPatient(patient.id);
                }}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <div className="text-center">
                      <p className="text-sm font-semibold text-primary">{patient.time}</p>
                      <span className={cn(
                        'badge-status text-[10px] mt-1',
                        patient.status === 'waiting' ? 'badge-warning' : 'badge-info'
                      )}>
                        {patient.status === 'waiting' ? 'Waiting' : 'Scheduled'}
                      </span>
                    </div>
                    <div>
                      <p className="font-medium">{patient.name}</p>
                      <p className="text-sm text-muted-foreground">
                        {patient.age} years • {patient.reason}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    {patient.hasLabResults && (
                      <span className="badge-success flex items-center gap-1">
                        <FlaskConical className="w-3 h-3" />
                        Lab Ready
                      </span>
                    )}
                    <button className="btn-primary text-sm py-1.5" onClick={() => navigate('/encounters')}>
                      Start Visit
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Pending Lab Results */}
        <div className="card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Pending Lab Results</h2>
            <span className="badge-warning">{pendingLabResults.length}</span>
          </div>
          <div className="divide-y divide-border">
            {pendingLabResults.map((lab) => (
              <div key={lab.id} className="p-4 hover:bg-muted/30 transition-colors cursor-pointer" onClick={() => navigate('/laboratory')}>
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-medium">{lab.patient}</p>
                    <p className="text-sm text-muted-foreground mt-0.5">{lab.test}</p>
                  </div>
                  <span className={cn(
                    'badge-status',
                    lab.priority === 'urgent' ? 'badge-critical' : 'badge-info'
                  )}>
                    {lab.priority}
                  </span>
                </div>
                <p className="text-xs text-muted-foreground mt-2">{lab.submitted}</p>
              </div>
            ))}
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-ghost text-sm text-primary w-full" onClick={() => navigate('/laboratory')}>View All Results →</button>
          </div>
        </div>
      </div>

      {/* Treatment Templates */}
      <div className="card-medical p-5">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold">Quick Treatment Templates</h2>
          <button className="btn-ghost text-sm" onClick={() => navigate('/treatment-templates')}>Manage Templates</button>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
          {[
            'Common Cold',
            'Hypertension',
            'Diabetes Check',
            'UTI Treatment',
            'Asthma Follow-up',
            'Pregnancy Check',
          ].map((template) => (
            <button
              key={template}
              onClick={() => navigate('/treatment-templates')}
              className="p-3 rounded-lg border border-border text-sm font-medium hover:bg-primary/5 hover:border-primary transition-all text-center"
            >
              {template}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
