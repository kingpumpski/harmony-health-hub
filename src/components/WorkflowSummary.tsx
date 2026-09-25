import { useMemo } from 'react';
import { Activity, CalendarDays, CreditCard, Users, BedDouble, Siren, Scissors, ShieldCheck, FlaskConical, Pill, ScanLine, Baby, AlertTriangle } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import type { UserRole } from '@/types';

type Card = { label: string; href: string; icon: typeof Activity; tone: string; surface: string };
const appointmentRoles: readonly UserRole[] = ['admin', 'practitioner', 'nurse', 'midwife', 'lab_technician', 'pharmacist', 'front_desk'];
const canAppointments = (role: UserRole) => appointmentRoles.includes(role);
const canBeds = (role: UserRole) => ['admin', 'nurse', 'midwife', 'specialist_nurse', 'practitioner'].includes(role);
const canEmergency = (role: UserRole) => ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'front_desk'].includes(role);
const canTheatre = (role: UserRole) => ['admin', 'practitioner', 'nurse', 'specialist_nurse'].includes(role);
const canClaims = (role: UserRole) => ['admin', 'accountant'].includes(role);
const clinicalRoles: readonly UserRole[] = ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'radiologist', 'radiology_technician'];

export default function WorkflowSummary() {
  const { user } = useAuth();
  const cards = useMemo<Card[]>(() => {
    if (!user) return [];
    const role = user.role;
    const common: Card[] = [
      ...(canAppointments(role) ? [
        { label: "Today's appointments", href: '/appointments', icon: CalendarDays, tone: 'text-primary', surface: 'bg-primary/5' },
      ] : []),
      ...(clinicalRoles.includes(role) ? [{ label: 'Critical alerts', href: '/notifications', icon: AlertTriangle, tone: 'text-critical', surface: 'bg-critical/5' }] : []),
    ];
    if (role === 'practitioner') return [...common,
      { label: 'Patients waiting', href: '/department-queue', icon: Users, tone: 'text-warning', surface: 'bg-warning/5' },
      { label: 'Laboratory', href: '/laboratory', icon: FlaskConical, tone: 'text-info', surface: 'bg-info/5' },
      { label: 'Radiology results', href: '/clinical-results', icon: ScanLine, tone: 'text-primary', surface: 'bg-primary/5' },
      { label: 'Radiology queue', href: '/radiology', icon: ScanLine, tone: 'text-info', surface: 'bg-info/5' },
      { label: 'Pharmacy', href: '/pharmacy', icon: Pill, tone: 'text-success', surface: 'bg-success/5' },
    ];
    if (role === 'radiology_technician') return [...common,
      { label: 'Radiology queue', href: '/radiology', icon: ScanLine, tone: 'text-primary', surface: 'bg-primary/5' },
      { label: 'Department queue', href: '/department-queue', icon: Users, tone: 'text-warning', surface: 'bg-warning/5' },
    ];
    if (role === 'radiologist') return [...common,
      { label: 'Radiology queue', href: '/radiology', icon: ScanLine, tone: 'text-primary', surface: 'bg-primary/5' },
      { label: 'Radiology results', href: '/clinical-results', icon: ScanLine, tone: 'text-info', surface: 'bg-info/5' },
    ];
    if (role === 'lab_technician') return [...common, { label: 'Laboratory', href: '/laboratory', icon: FlaskConical, tone: 'text-info', surface: 'bg-info/5' }];
    if (role === 'pharmacist') return [...common, { label: 'Pharmacy', href: '/pharmacy', icon: Pill, tone: 'text-success', surface: 'bg-success/5' }, { label: 'Patients waiting', href: '/department-queue', icon: Users, tone: 'text-warning', surface: 'bg-warning/5' }];
    if (role === 'accountant') return [
      { label: 'Payment approvals', href: '/accounts-approvals', icon: CreditCard, tone: 'text-warning', surface: 'bg-warning/5' },
      { label: 'Claims', href: '/insurance-claims', icon: ShieldCheck, tone: 'text-primary', surface: 'bg-primary/5' },
      { label: 'Billing', href: '/billing', icon: CreditCard, tone: 'text-success', surface: 'bg-success/5' },
    ];
    if (role === 'nurse' || role === 'midwife' || role === 'specialist_nurse') return [...common,
      { label: 'Department queue', href: '/department-queue', icon: Users, tone: 'text-warning', surface: 'bg-warning/5' },
      ...(canBeds(role) ? [{ label: 'Occupied beds', href: '/admissions', icon: BedDouble, tone: 'text-primary', surface: 'bg-primary/5' }] : []),
      ...(role === 'midwife' ? [{ label: 'Maternity', href: '/maternity', icon: Baby, tone: 'text-success', surface: 'bg-success/5' }] : []),
    ];
    if (role === 'front_desk') return [...common, { label: 'Department queue', href: '/department-queue', icon: Users, tone: 'text-warning', surface: 'bg-warning/5' }, { label: 'Emergency', href: '/emergency-board', icon: Siren, tone: 'text-critical', surface: 'bg-critical/5' }];
    return [...common,
      { label: 'Laboratory', href: '/laboratory', icon: FlaskConical, tone: 'text-info', surface: 'bg-info/5' },
      { label: 'Pharmacy', href: '/pharmacy', icon: Pill, tone: 'text-success', surface: 'bg-success/5' },
      { label: 'Radiology', href: '/radiology', icon: ScanLine, tone: 'text-primary', surface: 'bg-primary/5' },
      { label: 'Accounts', href: '/accounts-approvals', icon: CreditCard, tone: 'text-warning', surface: 'bg-warning/5' },
      ...(canBeds(role) ? [{ label: 'Admissions', href: '/admissions', icon: BedDouble, tone: 'text-primary', surface: 'bg-primary/5' }] : []),
      ...(canEmergency(role) ? [{ label: 'Emergency', href: '/emergency-board', icon: Siren, tone: 'text-critical', surface: 'bg-critical/5' }] : []),
      ...(canTheatre(role) ? [{ label: 'Theatre', href: '/theatre-board', icon: Scissors, tone: 'text-primary', surface: 'bg-primary/5' }] : []),
      ...(canClaims(role) ? [{ label: 'Claims', href: '/insurance-claims', icon: ShieldCheck, tone: 'text-warning', surface: 'bg-warning/5' }] : []),
    ];
  }, [user]);

  if (!user || !cards.length) return null;
  return (
    <section aria-label="Workflow navigation" className="mb-6">
      <div className="mb-3 flex items-end justify-between gap-3">
        <div>
          <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-primary">Quick access</p>
          <h2 className="text-base font-semibold">Your active workspaces</h2>
        </div>
        <span className="hidden text-xs text-muted-foreground sm:inline">Role-aware shortcuts</span>
      </div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6">
        {cards.map(({ label, href, icon: Icon, tone, surface }) => (
          <Link key={label} to={href} className={`group card-medical ${surface} min-w-0 p-3.5 transition-all duration-200 hover:-translate-y-0.5 hover:shadow-elevated focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring`}>
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="line-clamp-2 text-[11px] leading-tight text-muted-foreground">{label}</p>
                <p className={`mt-1 text-sm font-semibold ${tone}`}>Open workspace</p>
              </div>
              <div className="rounded-lg bg-background/70 p-1.5 transition-transform group-hover:scale-105"><Icon className={`h-4 w-4 shrink-0 ${tone}`} /></div>
            </div>
          </Link>
        ))}
      </div>
    </section>
  );
}
