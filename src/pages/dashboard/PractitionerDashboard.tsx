import { Link } from 'react-router-dom';
import { Users, Calendar, FileText, FlaskConical, Clock, Stethoscope, ClipboardList, Baby, Search } from 'lucide-react';
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
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div><p className="text-xs font-semibold uppercase tracking-wider text-primary">Clinical Workspace</p><h1 className="text-2xl font-heading font-bold">Today's Clinical Queue</h1><p className="text-muted-foreground">Prioritize patients, review results and move directly into the encounter workflow.</p></div>
        <div className="flex flex-wrap gap-3"><Link to="/appointments" className="btn-secondary"><Calendar className="w-4 h-4" />My Schedule</Link><Link to="/encounters" className="btn-primary"><Stethoscope className="w-4 h-4" />Start Encounter</Link></div>
      </div>

      {criticalAlerts.length > 0 && <div className="space-y-3">{criticalAlerts.map((alert) => <AlertBanner key={alert.id} type="critical" title={`Critical: ${alert.type} - ${alert.patient}`} message={`Reading: ${alert.value} • Recorded ${alert.time}. Immediate attention required.`} />)}</div>}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard title="Today's Patients" value={16} change="4 remaining" changeType="neutral" icon={Users} iconColor="text-primary" />
        <StatCard title="Pending Lab Results" value={8} change="2 urgent" changeType="negative" icon={FlaskConical} iconColor="text-warning" />
        <StatCard title="Encounters Today" value={12} change="75% completion" changeType="positive" icon={FileText} iconColor="text-success" />
        <StatCard title="Avg. Consultation" value="18m" change="On schedule" changeType="positive" icon={Clock} iconColor="text-info" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 card-medical overflow-hidden">
          <div className="p-5 border-b border-border flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h2 className="font-semibold">Upcoming Patients</h2><p className="text-xs text-muted-foreground mt-1">Open the encounter or patient record from the clinical queue.</p></div><Link to="/patients" className="btn-ghost text-sm"><Search className="w-4 h-4" />Find Patient</Link></div>
          <div className="divide-y divide-border">{upcomingPatients.map((patient) => <div key={patient.id} className="p-4 hover:bg-muted/30 transition-all"><div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div className="flex items-center gap-4 min-w-0"><div className="text-center shrink-0"><p className="text-sm font-semibold text-primary">{patient.time}</p><span className={cn('badge-status text-[10px] mt-1', patient.status === 'waiting' ? 'badge-warning' : 'badge-info')}>{patient.status === 'waiting' ? 'Waiting' : 'Scheduled'}</span></div><div className="min-w-0"><p className="font-medium truncate">{patient.name}</p><p className="text-sm text-muted-foreground truncate">{patient.age} years • {patient.reason}</p></div></div><div className="flex flex-wrap items-center gap-2 sm:justify-end">{patient.hasLabResults && <Link to="/laboratory" className="badge-success flex items-center gap-1"><FlaskConical className="w-3 h-3" />Lab Ready</Link>}<Link to="/encounters" className="btn-primary text-sm py-1.5">Start Visit</Link></div></div></div>)}</div>
        </div>

        <div className="card-medical overflow-hidden">
          <div className="p-5 border-b border-border flex items-center justify-between"><div><h2 className="font-semibold">Pending Lab Results</h2><p className="text-xs text-muted-foreground mt-1">Results requiring review</p></div><span className="badge-warning">{pendingLabResults.length}</span></div>
          <div className="divide-y divide-border">{pendingLabResults.map((lab) => <Link to="/laboratory" key={lab.id} className="block p-4 hover:bg-muted/30 transition-colors"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="font-medium truncate">{lab.patient}</p><p className="text-sm text-muted-foreground mt-0.5 truncate">{lab.test}</p></div><span className={cn('badge-status shrink-0', lab.priority === 'urgent' ? 'badge-critical' : 'badge-info')}>{lab.priority}</span></div><p className="text-xs text-muted-foreground mt-2">{lab.submitted}</p></Link>)}</div>
          <div className="p-4 border-t border-border"><Link to="/laboratory" className="btn-ghost text-sm text-primary w-full">View All Results →</Link></div>
        </div>
      </div>

      <div className="card-medical p-5">
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between mb-4"><div><h2 className="font-semibold">Clinical Shortcuts</h2><p className="text-sm text-muted-foreground">Common workflows for a Ghana-oriented outpatient and hospital environment.</p></div><Link to="/treatment-templates" className="btn-ghost text-sm">Manage Templates</Link></div>
        <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">{[
          { label: 'Common Cold', href: '/treatment-templates' },
          { label: 'Hypertension', href: '/treatment-templates' },
          { label: 'Diabetes Check', href: '/treatment-templates' },
          { label: 'UTI Treatment', href: '/treatment-templates' },
          { label: 'Pregnancy Check', href: '/maternity' },
          { label: 'Fertility Review', href: '/fertility' },
        ].map((template) => <Link key={template.label} to={template.href} className="p-3 rounded-lg border border-border text-sm font-medium hover:bg-primary/5 hover:border-primary transition-all text-center">{template.label}</Link>)}</div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Link to="/department-queue" className="card-medical p-4 hover:border-primary/40 transition-colors"><ClipboardList className="w-5 h-5 text-primary mb-2" /><p className="font-semibold">Department Queue</p><p className="text-sm text-muted-foreground mt-1">Coordinate service flow and patient movement.</p></Link>
        <Link to="/ai-clinical" className="card-medical p-4 hover:border-primary/40 transition-colors"><FileText className="w-5 h-5 text-primary mb-2" /><p className="font-semibold">AI Clinical Hub</p><p className="text-sm text-muted-foreground mt-1">Open assisted review with clinician oversight.</p></Link>
        <Link to="/fertility" className="card-medical p-4 hover:border-primary/40 transition-colors"><Baby className="w-5 h-5 text-primary mb-2" /><p className="font-semibold">Fertility Services</p><p className="text-sm text-muted-foreground mt-1">Move directly into fertility-specific workflows.</p></Link>
      </div>
    </div>
  );
}
