import { useCallback, useEffect, useMemo, useState } from 'react';
import { Activity, ArrowUpRight, BedDouble, ClipboardList, Gauge, HeartPulse, LogOut, MoveRight, RefreshCw, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import AdmissionManagement from './AdmissionManagement';

type Admission = {
  id: string;
  patient_id: string;
  admitted_at: string;
  discharged_at: string | null;
  ward: string | null;
  bed: string | null;
  reason: string | null;
  status: string;
};

type Bed = {
  id: string;
  ward_id: string;
  bed_number: string;
  status: string;
  patient_id: string | null;
  admission_id: string | null;
};

type Ward = {
  id: string;
  name: string;
  active: boolean;
};

type InpatientSummary = {
  activeAdmissions: number;
  admissionsToday: number;
  availableBeds: number;
  occupiedBeds: number;
  cleaningBeds: number;
  wards: number;
};

const sections = [
  { label: 'Admissions & Discharges', description: 'Start admissions, review active episodes and complete the discharge workflow.', href: '/admissions', icon: LogOut, tag: 'Lifecycle' },
  { label: 'Ward & Bed Management', description: 'Allocate beds, release beds and monitor ward capacity from one operational view.', href: '/ward-bed-board', icon: BedDouble, tag: 'Capacity' },
  { label: 'Patient Movements', description: 'Coordinate transfers and movement between inpatient locations through the canonical workflow.', href: '/care-transitions', icon: MoveRight, tag: 'Transfers' },
  { label: 'Nursing Handover', description: 'Maintain shift-to-shift inpatient continuity and clinical handover.', href: '/nursing-handover', icon: ClipboardList, tag: 'Continuity' },
  { label: 'Inpatient Census', description: 'Open the admissions workspace to review the current admitted-patient population and episodes.', href: '/admissions', icon: Users, tag: 'Census' },
  { label: 'Ward Operations', description: 'Open ward capacity and operational controls from the inpatient workspace.', href: '/ward-bed-board', icon: Activity, tag: 'Operations' },
];

const emptySummary: InpatientSummary = {
  activeAdmissions: 0,
  admissionsToday: 0,
  availableBeds: 0,
  occupiedBeds: 0,
  cleaningBeds: 0,
  wards: 0,
};

export default function InpatientManagement() {
  const [view, setView] = useState<'overview' | 'admissions'>('overview');
  const [summary, setSummary] = useState<InpatientSummary>(emptySummary);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');

  const loadSummary = useCallback(async () => {
    setLoading(true);
    setLoadError('');

    const [{ data: admissionData, error: admissionError }, { data: wardData, error: wardError }] = await Promise.all([
      supabase.rpc('get_admission_workspace', { _limit: 500 } as never),
      supabase.rpc('get_operational_workspace', { _module: 'ward', _limit: 500 } as never),
    ]);

    if (admissionError || wardError) {
      setSummary(emptySummary);
      setLoadError(admissionError?.message ?? wardError?.message ?? 'Unable to load inpatient summary.');
      setLoading(false);
      return;
    }

    const admissions = (Array.isArray(admissionData) ? admissionData : (admissionData as { admissions?: Admission[] } | null)?.admissions ?? []) as Admission[];
    const wards = ((wardData as { wards?: Ward[] } | null)?.wards ?? []) as Ward[];
    const beds = ((wardData as { beds?: Bed[] } | null)?.beds ?? []) as Bed[];
    const today = new Date().toDateString();

    setSummary({
      activeAdmissions: admissions.filter((row) => row.status === 'admitted' && !row.discharged_at).length,
      admissionsToday: admissions.filter((row) => new Date(row.admitted_at).toDateString() === today).length,
      availableBeds: beds.filter((row) => row.status === 'available' && !row.patient_id).length,
      occupiedBeds: beds.filter((row) => row.status === 'occupied').length,
      cleaningBeds: beds.filter((row) => row.status === 'cleaning').length,
      wards: wards.filter((row) => row.active !== false).length,
    });
    setLoading(false);
  }, []);

  useEffect(() => {
    void loadSummary();
  }, [loadSummary]);

  const occupancy = useMemo(() => {
    const totalManagedBeds = summary.availableBeds + summary.occupiedBeds + summary.cleaningBeds;
    return totalManagedBeds > 0 ? Math.round((summary.occupiedBeds / totalManagedBeds) * 100) : 0;
  }, [summary]);

  if (view === 'admissions') {
    return (
      <div className="space-y-4 animate-fade-in">
        <button type="button" onClick={() => setView('overview')} className="btn-secondary">
          ← Inpatient overview
        </button>
        <AdmissionManagement />
      </div>
    );
  }

  const metrics = [
    { label: 'Active census', value: summary.activeAdmissions, helper: 'Currently admitted', icon: Users },
    { label: 'Admissions today', value: summary.admissionsToday, helper: 'New inpatient episodes', icon: Activity },
    { label: 'Available beds', value: summary.availableBeds, helper: 'Ready for placement', icon: BedDouble },
    { label: 'Occupied beds', value: summary.occupiedBeds, helper: `${occupancy}% of managed beds`, icon: Gauge },
  ];

  return (
    <div className="space-y-7 animate-fade-in">
      <header className="rounded-3xl border border-border bg-card p-5 shadow-sm sm:p-7">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div className="min-w-0">
            <div className="mb-3 flex items-center gap-3">
              <div className="rounded-2xl bg-primary/10 p-3 text-primary"><BedDouble className="h-6 w-6" /></div>
              <span className="text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">Patient Care · Inpatient</span>
            </div>
            <h1 className="text-2xl font-heading font-bold tracking-tight sm:text-3xl">Inpatient command center</h1>
            <p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">
              One operational entry point for admission, placement, movement, nursing continuity, ward operations and discharge.
            </p>
          </div>
          <div className="flex flex-wrap gap-2 self-start lg:self-auto">
            <button type="button" onClick={() => void loadSummary()} disabled={loading} className="btn-secondary inline-flex items-center gap-2">
              <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} /> Refresh
            </button>
            <button type="button" onClick={() => setView('admissions')} className="btn-primary inline-flex items-center gap-2">
              New admission <ArrowUpRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      </header>

      <section aria-label="Inpatient summary" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {metrics.map(({ label, value, helper, icon: Icon }) => (
          <div key={label} className="card-medical rounded-2xl p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-[11px] text-muted-foreground">{label}</p>
                <p className="mt-1 text-2xl font-bold">{loading ? '—' : value}</p>
                <p className="mt-1 text-xs text-muted-foreground">{helper}</p>
              </div>
              <div className="rounded-xl bg-primary/10 p-2 text-primary"><Icon className="h-4 w-4" /></div>
            </div>
          </div>
        ))}
      </section>

      {loadError && (
        <section role="alert" className="rounded-2xl border border-destructive/30 bg-destructive/5 p-4">
          <p className="text-sm font-medium">Inpatient summary could not be loaded.</p>
          <p className="mt-1 text-xs text-muted-foreground">{loadError}</p>
          <button type="button" onClick={() => void loadSummary()} className="btn-secondary mt-3">Retry</button>
        </section>
      )}

      <section className="grid gap-4 lg:grid-cols-[1.25fr_0.75fr]">
        <div className="rounded-2xl border bg-card p-5 shadow-sm">
          <div className="mb-4 flex items-center justify-between gap-3">
            <div>
              <p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-primary">Capacity snapshot</p>
              <h2 className="text-lg font-semibold">Ward and bed status</h2>
            </div>
            <Link to="/ward-bed-board" className="btn-secondary text-xs">Open bed board</Link>
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Active wards</p><p className="mt-1 text-xl font-semibold">{loading ? '—' : summary.wards}</p></div>
            <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Cleaning beds</p><p className="mt-1 text-xl font-semibold">{loading ? '—' : summary.cleaningBeds}</p></div>
            <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Managed occupancy</p><p className="mt-1 text-xl font-semibold">{loading ? '—' : `${occupancy}%`}</p></div>
          </div>
        </div>
        <div className="rounded-2xl border bg-card p-5 shadow-sm">
          <div className="mb-3 flex items-center gap-2"><HeartPulse className="h-5 w-5 text-primary" /><div><p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-primary">Continuity</p><h2 className="font-semibold">Next inpatient actions</h2></div></div>
          <div className="space-y-2">
            <Link to="/nursing-handover" className="flex items-center justify-between rounded-xl border p-3 text-sm hover:bg-muted/50"><span>Nursing handover</span><ArrowUpRight className="h-4 w-4 text-muted-foreground" /></Link>
            <Link to="/care-transitions" className="flex items-center justify-between rounded-xl border p-3 text-sm hover:bg-muted/50"><span>Transfers & care transitions</span><ArrowUpRight className="h-4 w-4 text-muted-foreground" /></Link>
            <Link to="/admissions" className="flex items-center justify-between rounded-xl border p-3 text-sm hover:bg-muted/50"><span>Admission & discharge workflow</span><ArrowUpRight className="h-4 w-4 text-muted-foreground" /></Link>
          </div>
        </div>
      </section>

      <section>
        <div className="mb-3">
          <p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-primary">Inpatient workspaces</p>
          <h2 className="text-lg font-semibold">Choose an operational view</h2>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {sections.map(({ label, description, href, icon: Icon, tag }) => (
            <Link key={label} to={href} className="group card-medical rounded-2xl p-5 transition-all duration-200 hover:-translate-y-0.5 hover:shadow-elevated focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
              <div className="flex items-start justify-between gap-4">
                <div className="rounded-xl bg-primary/10 p-2.5 text-primary"><Icon className="h-5 w-5" /></div>
                <span className="rounded-full border border-border bg-background px-2.5 py-1 text-[10px] font-medium text-muted-foreground">{tag}</span>
              </div>
              <h3 className="mt-4 font-semibold">{label}</h3>
              <p className="mt-1 text-sm leading-5 text-muted-foreground">{description}</p>
              <div className="mt-4 flex items-center gap-1 text-xs font-medium text-primary">Open workspace <ArrowUpRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" /></div>
            </Link>
          ))}
        </div>
      </section>

      <section className="rounded-2xl border border-dashed border-border bg-muted/20 p-4 sm:p-5">
        <p className="text-sm font-medium">Clinical integrity</p>
        <p className="mt-1 text-xs leading-5 text-muted-foreground">
          Transfers, admissions, discharge and bed movements continue through secured server-side workflows. This overview only reads authorized workspace projections and does not bypass clinical authorization or database controls.
        </p>
      </section>
    </div>
  );
}
