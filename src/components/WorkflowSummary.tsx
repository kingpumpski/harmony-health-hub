import { useEffect, useMemo, useRef, useState } from 'react';
import { Activity, CalendarDays, CreditCard, Users, BedDouble, Siren, Scissors, ShieldCheck, FlaskConical, Pill, ScanLine, Baby, ClipboardCheck, AlertTriangle } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import type { UserRole } from '@/types';
import { playWorkflowSound } from '@/lib/workflowFeedback';

interface Counts {
  newAppointments: number; reviews: number; departmentWaiting: number; paymentApprovals: number;
  pharmacy: number; laboratory: number; imaging: number; nursing: number; maternity: number; admissions: number;
  emergency: number; theatre: number; claims: number; criticalAlerts: number; occupiedBeds: number; availableBeds: number;
}
const initialCounts: Counts = { newAppointments: 0, reviews: 0, departmentWaiting: 0, paymentApprovals: 0, pharmacy: 0, laboratory: 0, imaging: 0, nursing: 0, maternity: 0, admissions: 0, emergency: 0, theatre: 0, claims: 0, criticalAlerts: 0, occupiedBeds: 0, availableBeds: 0 };
const clinicalRoles: readonly UserRole[] = ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse'];
const appointmentRoles: readonly UserRole[] = ['admin', 'practitioner', 'nurse', 'midwife', 'lab_technician', 'pharmacist', 'front_desk'];
const bedRoles: readonly UserRole[] = ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse'];
const emergencyRoles: readonly UserRole[] = ['admin', 'practitioner', 'nurse', 'midwife', 'front_desk'];
const theatreRoles: readonly UserRole[] = ['admin', 'practitioner', 'nurse'];
const claimsRoles: readonly UserRole[] = ['admin', 'accountant'];
type Card = { label: string; value: number; href: string; icon: typeof Activity; tone: string; surface: string; urgent?: boolean };

export default function WorkflowSummary() {
  const { user } = useAuth();
  const [counts, setCounts] = useState<Counts>(initialCounts);
  const [department, setDepartment] = useState('');
  const previousQueueTotal = useRef(0);
  const hasLoadedQueue = useRef(false);

  useEffect(() => {
    if (!user?.id) return;
    let mounted = true;
    const load = async () => {
      const start = new Date(); start.setHours(0, 0, 0, 0);
      const end = new Date(); end.setHours(23, 59, 59, 999);
      const role = user.role;
      const canAppointments = appointmentRoles.includes(role);
      const canBeds = bedRoles.includes(role);
      const canEmergency = emergencyRoles.includes(role);
      const canTheatre = theatreRoles.includes(role);
      const canClaims = claimsRoles.includes(role);
      const { data: profile } = await supabase.from('profiles').select('department').eq('id', user.id).maybeSingle();
      const currentDepartment = profile?.department?.trim() ?? '';
      const departmentAliases = [currentDepartment.toLowerCase()].filter(Boolean);
      if (currentDepartment.toLowerCase().includes('lab')) departmentAliases.push('laboratory', 'lab');
      if (currentDepartment.toLowerCase().includes('radi')) departmentAliases.push('imaging', 'radiology');
      if (currentDepartment.toLowerCase().includes('pharm')) departmentAliases.push('pharmacy');
      if (currentDepartment.toLowerCase().includes('nurs')) departmentAliases.push('nursing');
      if (currentDepartment.toLowerCase().includes('matern')) departmentAliases.push('maternity');
      if (currentDepartment.toLowerCase().includes('account')) departmentAliases.push('accounts');

      const [appointments, reviews, queues, bedsOccupied, bedsAvailable, emergency, theatre, claims, critical] = await Promise.all([
        canAppointments ? supabase.from('appointments').select('id,patient_id,practitioner_id').gte('scheduled_at', start.toISOString()).lte('scheduled_at', end.toISOString()).eq('status', 'scheduled') : Promise.resolve({ data: [], error: null }),
        canAppointments ? supabase.from('appointments').select('id').gte('scheduled_at', start.toISOString()).lte('scheduled_at', end.toISOString()).in('status', ['checked_in', 'review']) : Promise.resolve({ data: [], error: null }),
        supabase.from('department_queues').select('patient_id,department,status').in('status', ['queued', 'claimed']),
        canBeds ? supabase.from('ward_beds').select('id').eq('status', 'occupied') : Promise.resolve({ data: [], error: null }),
        canBeds ? supabase.from('ward_beds').select('id').eq('status', 'available') : Promise.resolve({ data: [], error: null }),
        canEmergency ? supabase.from('emergency_cases').select('id').in('status', ['waiting', 'triage', 'treatment', 'observation']) : Promise.resolve({ data: [], error: null }),
        canTheatre ? supabase.from('theatre_cases').select('id').gte('scheduled_start', start.toISOString()).lte('scheduled_start', end.toISOString()).in('status', ['requested', 'approved', 'scheduled', 'in_progress']) : Promise.resolve({ data: [], error: null }),
        canClaims ? supabase.from('insurance_claims').select('id').in('status', ['draft', 'submitted', 'acknowledged', 'under_review', 'resubmission_required']) : Promise.resolve({ data: [], error: null }),
        supabase.from('notifications').select('id').eq('is_read', false).eq('severity', 'critical'),
      ]);
      if (!mounted) return;

      const queueRows = (queues.data ?? []) as Array<{ patient_id: string | null; department: string | null; status: string }>;
      const countPatients = (names: string[]) => new Set(queueRows.filter((row) => names.includes((row.department ?? '').toLowerCase())).map((row) => row.patient_id).filter(Boolean)).size;
      const appointmentRows = (appointments.data ?? []) as Array<{ practitioner_id: string | null }>;
      const visibleAppointments = role === 'practitioner' ? appointmentRows.filter((row) => !row.practitioner_id || row.practitioner_id === user.id).length : appointmentRows.length;
      const nextQueueTotal = queueRows.length;
      if (hasLoadedQueue.current && nextQueueTotal > previousQueueTotal.current) playWorkflowSound('info');
      previousQueueTotal.current = nextQueueTotal;
      hasLoadedQueue.current = true;
      setDepartment(currentDepartment);
      setCounts({ newAppointments: visibleAppointments, reviews: reviews.data?.length ?? 0, departmentWaiting: currentDepartment ? countPatients(departmentAliases) : 0, paymentApprovals: countPatients(['accounts']), pharmacy: countPatients(['pharmacy']), laboratory: countPatients(['laboratory', 'lab']), imaging: countPatients(['imaging', 'radiology']), nursing: countPatients(['nursing']), maternity: countPatients(['maternity']), admissions: countPatients(['admission', 'admissions']), emergency: emergency.data?.length ?? 0, theatre: theatre.data?.length ?? 0, claims: claims.data?.length ?? 0, criticalAlerts: critical.data?.length ?? 0, occupiedBeds: bedsOccupied.data?.length ?? 0, availableBeds: bedsAvailable.data?.length ?? 0 });
    };

    void load();
    const channel = supabase.channel(`workflow-summary-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'department_queues' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, (payload) => { if (payload.eventType === 'INSERT' && (payload.new as { severity?: string }).severity === 'critical') playWorkflowSound('critical'); void load(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'triage_assessments' }, (payload) => { if (payload.eventType === 'INSERT' && String((payload.new as { priority?: string }).priority).toLowerCase() === 'critical') playWorkflowSound('critical'); void load(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ward_beds' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'emergency_cases' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'theatre_cases' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'insurance_claims' }, () => void load())
      .subscribe();
    return () => { mounted = false; void supabase.removeChannel(channel); };
  }, [user]);

  const cards = useMemo<Card[]>(() => {
    if (!user) return [];
    const role = user.role;
    const common: Card[] = [
      ...(appointmentRoles.includes(role) ? [
        { label: "Today's appointments", value: counts.newAppointments, href: '/appointments', icon: CalendarDays, tone: 'text-primary', surface: 'bg-primary/5', urgent: counts.newAppointments > 0 },
        { label: "Today's clinical reviews", value: counts.reviews, href: '/appointments', icon: ClipboardCheck, tone: 'text-success', surface: 'bg-success/5', urgent: counts.reviews > 0 },
      ] : []),
      ...(clinicalRoles.includes(role) && counts.criticalAlerts > 0 ? [{ label: 'Critical alerts', value: counts.criticalAlerts, href: '/notifications', icon: AlertTriangle, tone: 'text-critical', surface: 'bg-critical/5', urgent: true }] : []),
    ];
    if (role === 'practitioner') return [...common, { label: 'Patients waiting for you', value: counts.departmentWaiting, href: '/department-queue', icon: Users, tone: 'text-warning', surface: 'bg-warning/5', urgent: counts.departmentWaiting > 0 }, { label: 'Laboratory waiting', value: counts.laboratory, href: '/laboratory', icon: FlaskConical, tone: 'text-info', surface: 'bg-info/5', urgent: counts.laboratory > 0 }, { label: 'Radiology waiting', value: counts.imaging, href: '/radiology', icon: ScanLine, tone: 'text-primary', surface: 'bg-primary/5', urgent: counts.imaging > 0 }, { label: 'Pharmacy waiting', value: counts.pharmacy, href: '/pharmacy', icon: Pill, tone: 'text-success', surface: 'bg-success/5', urgent: counts.pharmacy > 0 }];
    if (role === 'lab_technician') return [...common, { label: 'Laboratory waiting', value: counts.laboratory, href: '/laboratory', icon: FlaskConical, tone: 'text-info', surface: 'bg-info/5', urgent: counts.laboratory > 0 }];
    if (role === 'pharmacist') return [...common, { label: 'Pharmacy waiting', value: counts.pharmacy, href: '/pharmacy', icon: Pill, tone: 'text-success', surface: 'bg-success/5', urgent: counts.pharmacy > 0 }, { label: 'Patients waiting', value: counts.departmentWaiting, href: '/department-queue', icon: Users, tone: 'text-warning', surface: 'bg-warning/5', urgent: counts.departmentWaiting > 0 }];
    if (role === 'accountant') return [{ label: 'Payment approvals', value: counts.paymentApprovals, href: '/accounts-approvals', icon: CreditCard, tone: 'text-warning', surface: 'bg-warning/5', urgent: counts.paymentApprovals > 0 }, { label: 'Claims attention', value: counts.claims, href: '/insurance-claims', icon: ShieldCheck, tone: 'text-primary', surface: 'bg-primary/5', urgent: counts.claims > 0 }];
    if (role === 'nurse' || role === 'midwife' || role === 'specialist_nurse') return [...common, { label: 'Department waiting', value: counts.departmentWaiting, href: '/department-queue', icon: Users, tone: 'text-warning', surface: 'bg-warning/5', urgent: counts.departmentWaiting > 0 }, { label: 'Nursing queue', value: counts.nursing, href: '/department-queue', icon: Activity, tone: 'text-info', surface: 'bg-info/5', urgent: counts.nursing > 0 }, { label: 'Admissions waiting', value: counts.admissions, href: '/admissions', icon: BedDouble, tone: 'text-primary', surface: 'bg-primary/5', urgent: counts.admissions > 0 }, ...(role === 'midwife' ? [{ label: 'Maternity waiting', value: counts.maternity, href: '/maternity', icon: Baby, tone: 'text-success', surface: 'bg-success/5', urgent: counts.maternity > 0 }] : [])];
    if (role === 'front_desk') return [...common, { label: 'Department waiting', value: counts.departmentWaiting, href: '/department-queue', icon: Users, tone: 'text-warning', surface: 'bg-warning/5', urgent: counts.departmentWaiting > 0 }, { label: 'Emergency queue', value: counts.emergency, href: '/emergency-board', icon: Siren, tone: 'text-critical', surface: 'bg-critical/5', urgent: counts.emergency > 0 }];
    return [...common, { label: 'Laboratory waiting', value: counts.laboratory, href: '/laboratory', icon: FlaskConical, tone: 'text-info', surface: 'bg-info/5', urgent: counts.laboratory > 0 }, { label: 'Pharmacy waiting', value: counts.pharmacy, href: '/pharmacy', icon: Pill, tone: 'text-success', surface: 'bg-success/5', urgent: counts.pharmacy > 0 }, { label: 'Radiology waiting', value: counts.imaging, href: '/radiology', icon: ScanLine, tone: 'text-primary', surface: 'bg-primary/5', urgent: counts.imaging > 0 }, { label: 'Accounts waiting', value: counts.paymentApprovals, href: '/accounts-approvals', icon: CreditCard, tone: 'text-warning', surface: 'bg-warning/5', urgent: counts.paymentApprovals > 0 }, { label: 'Admissions waiting', value: counts.admissions, href: '/admissions', icon: BedDouble, tone: 'text-primary', surface: 'bg-primary/5', urgent: counts.admissions > 0 }, { label: 'Emergency queue', value: counts.emergency, href: '/emergency-board', icon: Siren, tone: 'text-critical', surface: 'bg-critical/5', urgent: counts.emergency > 0 }, { label: 'Theatre today', value: counts.theatre, href: '/theatre-board', icon: Scissors, tone: 'text-primary', surface: 'bg-primary/5', urgent: counts.theatre > 0 }, { label: 'Claims attention', value: counts.claims, href: '/insurance-claims', icon: ShieldCheck, tone: 'text-warning', surface: 'bg-warning/5', urgent: counts.claims > 0 }, ...(bedRoles.includes(role) ? [{ label: 'Occupied beds', value: counts.occupiedBeds, href: '/ward-bed-board', icon: Users, tone: 'text-critical', surface: 'bg-critical/5', urgent: false }, { label: 'Available beds', value: counts.availableBeds, href: '/ward-bed-board', icon: BedDouble, tone: 'text-success', surface: 'bg-success/5', urgent: false }] : [])];
  }, [counts, user, department]);

  if (!user) return null;
  return <section aria-label="Live workflow queues" className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6 gap-3 mb-6">{cards.map(({ label, value, href, icon: Icon, tone, surface, urgent }) => <Link key={label} to={href} className={`card-medical ${surface} p-3 min-w-0 transition-all duration-300 hover:-translate-y-1 hover:shadow-elevated ${urgent && value > 0 ? 'ring-1 ring-primary/20' : ''}`}><div className="flex items-start justify-between gap-2"><div className="min-w-0"><p className="text-[11px] leading-tight text-muted-foreground line-clamp-2">{label}</p><p className={`text-2xl font-bold mt-1 tabular-nums transition-all duration-300 ${urgent && value > 0 ? 'animate-pulse' : ''}`}>{value}</p><p className="text-[10px] text-muted-foreground mt-1">Open queue</p></div><Icon className={`w-5 h-5 shrink-0 ${tone}`} /></div></Link>)}</section>;
}
