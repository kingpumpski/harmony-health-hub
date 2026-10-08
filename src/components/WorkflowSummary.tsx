import { useMemo } from 'react';
import { Activity, CalendarDays, CreditCard, Users, BedDouble, Siren, Scissors, ShieldCheck, FlaskConical, Pill, ScanLine, Baby, AlertTriangle, Settings, Cloud, Upload, FileText, Utensils } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import type { UserRole } from '@/types';

type Card = { label: string; href: string; icon: typeof Activity; tone: string; surface: string };
const appointmentRoles: readonly UserRole[] = ['admin', 'practitioner', 'nurse', 'midwife', 'front_desk'];
const canAppointments = (role: UserRole) => appointmentRoles.includes(role);
const clinicalRoles: readonly UserRole[] = ['practitioner','nurse','midwife','specialist_nurse','radiologist','radiology_technician'];

export default function WorkflowSummary() {
  const { user } = useAuth();
  const cards = useMemo<Card[]>(() => {
    if (!user) return [];
    const role = user.role;
    const make = (label: string, href: string, icon: typeof Activity, tone = 'text-primary', surface = 'bg-primary/5'): Card => ({ label, href, icon, tone, surface });
    const common: Card[] = [
      ...(canAppointments(role) ? [make("Today's appointments", '/appointments', CalendarDays)] : []),
      ...(clinicalRoles.includes(role) ? [make('Critical alerts', '/notifications', AlertTriangle, 'text-critical', 'bg-critical/5')] : []),
    ];
    if (role === 'admin') return [make('User management','/admin/users',Users),make('Role permissions','/admin/roles',ShieldCheck),make('System settings','/admin/settings',Settings),make('Audit logs','/admin/logs',FileText),make('Offline synchronization','/admin/offline-sync',Cloud),make('Data import','/admin/data-import',Upload),make('Reports','/reports',FileText)];
    if (role === 'practitioner') return [...common,make('Patients waiting','/department-queue',Users,'text-warning','bg-warning/5'),make('Laboratory results','/lab-results',FlaskConical,'text-info','bg-info/5'),make('Radiology results','/clinical-results',ScanLine),make('Medication administration','/medications',Pill,'text-success','bg-success/5'),make('Inpatient','/inpatient',BedDouble,'text-info','bg-info/5'),make('Emergency','/emergency-board',Siren,'text-critical','bg-critical/5'),make('Theatre','/theatre-board',Scissors)];
    if (role === 'nurse' || role === 'specialist_nurse') return [...common,make('Department queue','/department-queue',Users,'text-warning','bg-warning/5'),make('Inpatient','/inpatient',BedDouble),make('Medication administration','/medications',Pill,'text-success','bg-success/5'),make('Nursing handover','/nursing-handover',FileText),make('Vitals & triage','/vitals',Activity,'text-critical','bg-critical/5')];
    if (role === 'midwife') return [...common,make('Maternity','/maternity',Baby,'text-success','bg-success/5'),make('Inpatient','/inpatient',BedDouble),make('Medication administration','/medications',Pill,'text-success','bg-success/5'),make('Nursing handover','/nursing-handover',FileText),make('Vitals & triage','/vitals',Activity,'text-critical','bg-critical/5')];
    if (role === 'lab_technician') return [...common,make('Laboratory worklist','/laboratory',FlaskConical,'text-info','bg-info/5'),make('Result entry & approval','/results-entry',FileText),make('Department queue','/department-queue',Users,'text-warning','bg-warning/5')];
    if (role === 'radiologist') return [...common,make('Imaging worklist','/radiology',ScanLine)];
    if (role === 'radiology_technician') return [make('Imaging worklist','/radiology',ScanLine),make('Acquisition queue','/department-queue',Users,'text-warning','bg-warning/5'),make('Urgent studies','/radiology',Siren,'text-critical','bg-critical/5')];
    if (role === 'pharmacist') return [...common,make('Dispensing','/pharmacy',Pill,'text-success','bg-success/5'),make('Inventory & stock alerts','/stock-alerts',Activity,'text-warning','bg-warning/5'),make('Pharmacy queue','/department-queue',Users,'text-warning','bg-warning/5')];
    if (role === 'accountant') return [make('Payment approvals','/accounts-approvals',CreditCard,'text-warning','bg-warning/5'),make('Billing','/billing',CreditCard,'text-success','bg-success/5'),make('Insurance claims','/insurance-claims',ShieldCheck),make('Finance queue','/finance',FileText,'text-warning','bg-warning/5'),make('Financial reports','/financial-reports',FileText)];
    if (role === 'front_desk') return [...common,make('Patient registration','/registration',Users),make('Department queue','/department-queue',Users,'text-warning','bg-warning/5'),make('Payment handoff','/billing',CreditCard,'text-success','bg-success/5')];
    if (role === 'canteen') return [make('Meal orders','/orders',Utensils),make('Dietary plans','/dietary-plans',FileText,'text-warning','bg-warning/5'),make('Meal menu','/menu',Utensils,'text-success','bg-success/5'),make('Delivery queue','/orders',Users,'text-warning','bg-warning/5')];
    if (role === 'patient') return [make('My health record','/patient-portal',Activity),make('Appointments','/appointments',CalendarDays),make('Telemedicine','/telemedicine',Activity)];
    if (role === 'it_admin') return [make('IT support','/it-support',ShieldCheck),make('Offline synchronization','/admin/offline-sync',Cloud),make('Audit logs','/admin/logs',FileText),make('System notifications','/notifications',Activity,'text-warning','bg-warning/5')];
    return [];
  }, [user]);

  if (!user || !cards.length) return null;
  return (
    <section aria-label="Workflow navigation" className="mt-8 border-t border-border pt-6">
      <div className="mb-3 flex items-end justify-between gap-3">
        <div>
          <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-primary">Quick access</p>
          <h2 className="text-base font-semibold">Your active workspaces</h2>
        </div>
        <span className="hidden text-xs text-muted-foreground sm:inline">Role-specific operational shortcuts</span>
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
