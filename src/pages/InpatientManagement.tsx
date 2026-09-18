import { useState } from 'react';
import { BedDouble, ClipboardList, LogOut, MoveRight, Users, Activity } from 'lucide-react';
import { Link } from 'react-router-dom';
import AdmissionManagement from './AdmissionManagement';

const sections = [
  { label: 'Admissions & Discharges', description: 'Start admissions, manage active episodes and complete discharge workflow.', href: '/admissions', icon: LogOut },
  { label: 'Ward & Bed Management', description: 'Configure wards, allocate beds, release beds and monitor capacity.', href: '/ward-bed-board', icon: BedDouble },
  { label: 'Patient Movements', description: 'Centralize transfers and movement between inpatient locations.', href: '/care-transitions', icon: MoveRight },
  { label: 'Nursing Handover', description: 'Maintain shift-to-shift inpatient continuity and clinical handover.', href: '/nursing-handover', icon: ClipboardList },
  { label: 'Inpatient Census', description: 'Use the active admission view to monitor the current inpatient population.', href: '/admissions', icon: Users },
  { label: 'Ward Operations', description: 'Open ward capacity and operational controls from the same inpatient workspace.', href: '/ward-bed-board', icon: Activity },
];

export default function InpatientManagement() {
  const [view, setView] = useState<'overview' | 'admissions'>('overview');

  if (view === 'admissions') {
    return <div className="space-y-4">
      <button type="button" onClick={() => setView('overview')} className="btn-secondary">← Inpatient overview</button>
      <AdmissionManagement />
    </div>;
  }

  return <div className="space-y-6 animate-fade-in">
    <header>
      <div className="flex items-center gap-3"><BedDouble className="h-7 w-7 text-primary" /><div><h1 className="text-2xl font-heading font-bold">Inpatient</h1><p className="text-sm text-muted-foreground">The complete admitted-patient lifecycle: admission, placement, movement, nursing continuity, ward operations and discharge.</p></div></div>
    </header>
    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
      {sections.map(section => { const Icon = section.icon; return <Link key={section.label} to={section.href} className="card-medical group p-5 transition-transform hover:-translate-y-0.5"><div className="flex items-start justify-between gap-4"><div className="rounded-xl bg-primary/10 p-3 text-primary"><Icon className="h-5 w-5" /></div><span className="text-xs text-muted-foreground">Open</span></div><h2 className="mt-4 font-semibold">{section.label}</h2><p className="mt-1 text-sm text-muted-foreground">{section.description}</p></Link>; })}
    </section>
    <section className="card-medical p-5">
      <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-semibold">Inpatient admission workspace</h2><p className="text-sm text-muted-foreground">Admissions remain the clinical starting point; ward and bed management is a supporting operational view.</p></div><button type="button" onClick={() => setView('admissions')} className="btn-primary">Open admissions</button></div>
    </section>
  </div>;
}
