import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { BedDouble, HeartPulse, Syringe, FileText, AlertTriangle, Users, ThermometerSun, Activity } from 'lucide-react';
import StatCard from '@/components/ui/StatCard';
import AlertBanner from '@/components/ui/AlertBanner';
import { cn } from '@/lib/utils';

const inpatients = [
  { id: 1, bed: 'W1-B01', name: 'James Wilson', diagnosis: 'Post-surgery recovery', lastVitals: '15 min ago', status: 'stable', alerts: [] },
  { id: 2, bed: 'W1-B02', name: 'Emma Taylor', diagnosis: 'Pneumonia', lastVitals: '8 min ago', status: 'critical', alerts: ['High Fever'] },
  { id: 3, bed: 'W1-B03', name: 'Michael Brown', diagnosis: 'Cardiac monitoring', lastVitals: '5 min ago', status: 'attention', alerts: ['BP Elevated'] },
  { id: 4, bed: 'W1-B04', name: 'Lisa Anderson', diagnosis: 'Diabetes management', lastVitals: '20 min ago', status: 'stable', alerts: [] },
  { id: 5, bed: 'W2-B01', name: 'David Miller', diagnosis: 'Hip replacement', lastVitals: '12 min ago', status: 'stable', alerts: [] },
];

const pendingMedications = [
  { id: 1, patient: 'James Wilson', bed: 'W1-B01', drug: 'Paracetamol 500mg', time: '10:00 AM', status: 'due' },
  { id: 2, patient: 'Emma Taylor', bed: 'W1-B02', drug: 'Amoxicillin 500mg', time: '10:00 AM', status: 'overdue' },
  { id: 3, patient: 'Michael Brown', bed: 'W1-B03', drug: 'Metoprolol 50mg', time: '10:30 AM', status: 'upcoming' },
  { id: 4, patient: 'Lisa Anderson', bed: 'W1-B04', drug: 'Insulin 10 units', time: '10:30 AM', status: 'upcoming' },
];

const temperatureChart = [
  { time: '6AM', temp: 37.2 },
  { time: '8AM', temp: 37.5 },
  { time: '10AM', temp: 38.1 },
  { time: '12PM', temp: 38.8 },
  { time: '2PM', temp: 39.2 },
  { time: '4PM', temp: 38.5 },
];

export default function NurseDashboard() {
  const navigate = useNavigate();
  const [selectedWard, setSelectedWard] = useState('all');

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Nursing Station</h1>
          <p className="text-muted-foreground">Ward 1 & 2 • Day Shift</p>
        </div>
        <div className="flex gap-3">
          <button className="btn-secondary" onClick={() => navigate('/records')}>
            <FileText className="w-4 h-4" />
            Nursing Notes
          </button>
          <button className="btn-primary" onClick={() => navigate('/vitals')}>
            <HeartPulse className="w-4 h-4" />
            Record Vitals
          </button>
        </div>
      </div>

      {/* Critical Alert */}
      <AlertBanner
        type="critical"
        title="Immediate Attention Required - Bed W1-B02"
        message="Patient Emma Taylor has high fever (39.8°C). Doctor has been notified. Please monitor closely."
      />

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Total Inpatients"
          value={24}
          change="2 new admissions"
          changeType="neutral"
          icon={BedDouble}
          iconColor="text-primary"
        />
        <StatCard
          title="Pending Medications"
          value={12}
          change="2 overdue"
          changeType="negative"
          icon={Syringe}
          iconColor="text-warning"
        />
        <StatCard
          title="Vitals Due"
          value={6}
          change="Next in 15 min"
          changeType="neutral"
          icon={HeartPulse}
          iconColor="text-info"
        />
        <StatCard
          title="Critical Patients"
          value={2}
          change="Requires attention"
          changeType="negative"
          icon={AlertTriangle}
          iconColor="text-critical"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Inpatient List */}
        <div className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Inpatient Overview</h2>
            <div className="flex gap-2">
              {['all', 'critical', 'attention'].map((filter) => (
                <button
                  key={filter}
                  onClick={() => setSelectedWard(filter)}
                  className={cn(
                    'px-3 py-1.5 rounded-lg text-sm font-medium transition-colors capitalize',
                    selectedWard === filter
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-muted text-muted-foreground hover:bg-muted/80'
                  )}
                >
                  {filter}
                </button>
              ))}
            </div>
          </div>
          <div className="divide-y divide-border">
            {inpatients
              .filter(p => selectedWard === 'all' || p.status === selectedWard)
              .map((patient) => (
              <div
                key={patient.id}
                className={cn(
                  'p-4 transition-colors hover:bg-muted/30',
                  patient.status === 'critical' && 'bg-critical/5 border-l-2 border-l-critical',
                  patient.status === 'attention' && 'bg-warning/5 border-l-2 border-l-warning'
                )}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <div className="text-center px-3 py-2 bg-muted rounded-lg">
                      <p className="text-xs text-muted-foreground">Bed</p>
                      <p className="font-bold text-sm">{patient.bed}</p>
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <p className="font-medium">{patient.name}</p>
                        {patient.alerts.length > 0 && (
                          <span className="badge-critical pulse-critical flex items-center gap-1">
                            <AlertTriangle className="w-3 h-3" />
                            {patient.alerts[0]}
                          </span>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground">{patient.diagnosis}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="text-right">
                      <p className="text-xs text-muted-foreground">Last Vitals</p>
                      <p className="text-sm font-medium">{patient.lastVitals}</p>
                    </div>
                    <button className="btn-secondary text-sm py-1.5" onClick={() => navigate('/vitals')}>
                      <HeartPulse className="w-4 h-4" />
                      Vitals
                    </button>
                    <button className="btn-ghost text-sm py-1.5" onClick={() => navigate('/pharmacy')}>
                      <Syringe className="w-4 h-4" />
                      Meds
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Medication Schedule */}
        <div className="card-medical">
          <div className="p-5 border-b border-border">
            <h2 className="font-semibold">Medication Schedule</h2>
          </div>
          <div className="divide-y divide-border max-h-96 overflow-y-auto">
            {pendingMedications.map((med) => (
              <div
                key={med.id}
                className={cn(
                  'p-4 cursor-pointer hover:bg-muted/30 transition-colors',
                  med.status === 'overdue' && 'bg-critical/5'
                )}
                onClick={() => navigate('/pharmacy')}
              >
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-medium text-sm">{med.patient}</p>
                    <p className="text-xs text-muted-foreground">{med.bed}</p>
                    <p className="text-sm mt-1">{med.drug}</p>
                  </div>
                  <div className="text-right">
                    <span className={cn(
                      'badge-status',
                      med.status === 'overdue' && 'badge-critical pulse-critical',
                      med.status === 'due' && 'badge-warning',
                      med.status === 'upcoming' && 'badge-info'
                    )}>
                      {med.time}
                    </span>
                    <button className="btn-primary text-xs py-1 px-2 mt-2 w-full" onClick={() => navigate('/pharmacy')}>
                      Administer
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Temperature Monitoring */}
      <div className="card-medical p-5">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="font-semibold">Temperature Monitoring - Emma Taylor (W1-B02)</h2>
            <p className="text-sm text-muted-foreground">Last 12 hours</p>
          </div>
          <span className="badge-critical">Current: 38.5°C</span>
        </div>
        <div className="flex items-end gap-4 h-40">
          {temperatureChart.map((point, idx) => {
            const height = ((point.temp - 36) / 4) * 100;
            const isHigh = point.temp >= 38;
            return (
              <div key={idx} className="flex-1 flex flex-col items-center gap-2">
                <div
                  className={cn(
                    'w-full rounded-t-lg transition-all',
                    isHigh ? 'bg-critical' : 'bg-primary'
                  )}
                  style={{ height: `${height}%` }}
                />
                <span className="text-xs text-muted-foreground">{point.time}</span>
                <span className={cn(
                  'text-xs font-medium',
                  isHigh ? 'text-critical' : 'text-foreground'
                )}>
                  {point.temp}°C
                </span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
