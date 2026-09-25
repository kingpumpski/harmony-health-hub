import { BedDouble, ClipboardList, LogOut, MoveRight, Users, Activity, ArrowUpRight, Gauge, HeartPulse } from 'lucide-react';
import { Link } from 'react-router-dom';
import AdmissionManagement from './AdmissionManagement';
import { useState } from 'react';

const sections = [
  { label: 'Admissions & Discharges', description: 'Start admissions, manage active episodes and complete discharge workflow.', href: '/admissions', icon: LogOut, tag: 'Lifecycle' },
  { label: 'Ward & Bed Management', description: 'Allocate beds, release beds and monitor ward capacity from one operational view.', href: '/ward-bed-board', icon: BedDouble, tag: 'Capacity' },
  { label: 'Patient Movements', description: 'Coordinate transfers and movement between inpatient locations using the canonical workflow.', href: '/care-transitions', icon: MoveRight, tag: 'Transfers' },
  { label: 'Nursing Handover', description: 'Maintain shift-to-shift inpatient continuity and clinical handover.', href: '/nursing-handover', icon: ClipboardList, tag: 'Continuity' },
  { label: 'Inpatient Census', description: 'Monitor the current admitted-patient population and active episodes.', href: '/admissions', icon: Users, tag: 'Census' },
  { label: 'Ward Operations', description: 'Open ward capacity and operational controls from the inpatient workspace.', href: '/ward-bed-board', icon: Activity, tag: 'Operations' },
];

export default function InpatientManagement() {
  const [view, setView] = useState<'overview' | 'admissions'>('overview');

  if (view === 'admissions') return <div className="space-y-4 animate-fade-in"><button type="button" onClick={() => setView('overview')} className="btn-secondary">← Inpatient overview</button><AdmissionManagement /></div>;

  return (
    <div className="space-y-7 animate-fade-in">
      <header className="rounded-3xl border border-border bg-card p-5 shadow-sm sm:p-7">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div className="min-w-0">
            <div className="mb-3 flex items-center gap-3"><div className="rounded-2xl bg-primary/10 p-3 text-primary"><BedDouble className="h-6 w-6" /></div><span className="text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">Patient Care · Inpatient</span></div>
            <h1 className="text-2xl font-heading font-bold tracking-tight sm:text-3xl">Inpatient command center</h1>
            <p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">One workspace for the admitted-patient lifecycle — admission, placement, movement, nursing continuity, ward operations and discharge.</p>
          </div>
          <button type="button" onClick={() => setView('admissions')} className="btn-primary inline-flex items-center gap-2 self-start lg:self-auto">Open admissions <ArrowUpRight className="h-4 w-4" /></button>
        </div>
      </header>

      <section className="grid gap-3 sm:grid-cols-3">
        {[{label:'Active census',value:'Inpatient',icon:Users},{label:'Bed operations',value:'Capacity & placement',icon:Gauge},{label:'Clinical continuity',value:'Handover & movement',icon:HeartPulse}].map(({label,value,icon:Icon}) => <div key={label} className="card-medical rounded-2xl p-4"><div className="flex items-center gap-3"><div className="rounded-xl bg-primary/10 p-2 text-primary"><Icon className="h-4 w-4"/></div><div><p className="text-[11px] text-muted-foreground">{label}</p><p className="text-sm font-semibold">{value}</p></div></div></div>)}
      </section>

      <section>
        <div className="mb-3"><p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-primary">Inpatient workspaces</p><h2 className="text-lg font-semibold">Choose an operational view</h2></div>
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {sections.map(({label,description,href,icon:Icon,tag}) => <Link key={label} to={href} className="group card-medical rounded-2xl p-5 transition-all duration-200 hover:-translate-y-0.5 hover:shadow-elevated focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            <div className="flex items-start justify-between gap-4"><div className="rounded-xl bg-primary/10 p-2.5 text-primary"><Icon className="h-5 w-5"/></div><span className="rounded-full border border-border bg-background px-2.5 py-1 text-[10px] font-medium text-muted-foreground">{tag}</span></div>
            <h3 className="mt-4 font-semibold">{label}</h3><p className="mt-1 text-sm leading-5 text-muted-foreground">{description}</p>
            <div className="mt-4 flex items-center gap-1 text-xs font-medium text-primary">Open workspace <ArrowUpRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5"/></div>
          </Link>)}
        </div>
      </section>

      <section className="rounded-2xl border border-dashed border-border bg-muted/20 p-4 sm:p-5"><p className="text-sm font-medium">Clinical integrity</p><p className="mt-1 text-xs leading-5 text-muted-foreground">Transfers and bed movements continue through the secured inpatient workflow. This page is an operational entry point and does not bypass clinical authorization or database controls.</p></section>
    </div>
  );
}