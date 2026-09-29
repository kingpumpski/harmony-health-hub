import { ChevronDown } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import SpecialistReferralCard from '@/components/SpecialistReferralCard';
import FinancialSettlementCard from '@/components/FinancialSettlementCard';
import FrontDeskDashboard from './dashboard/FrontDeskDashboard';
import PractitionerDashboard from './dashboard/PractitionerDashboard';
import NurseDashboard from './dashboard/NurseDashboard';
import LabTechDashboard from './dashboard/LabTechDashboard';
import PharmacyDashboard from './dashboard/PharmacyDashboard';
import AccountsDashboard from './dashboard/AccountsDashboard';
import AdminDashboard from './dashboard/AdminDashboard';
import CanteenDashboard from './dashboard/CanteenDashboard';
import RadiologistDashboard from './dashboard/RadiologistDashboard';
import RadiologyTechnicianDashboard from './dashboard/RadiologyTechnicianDashboard';
import PatientDashboard from './dashboard/PatientDashboard';
import ITAdminDashboard from './dashboard/ITAdminDashboard';
import { AlertTriangle } from 'lucide-react';
import type { UserRole } from '@/types';

export default function Dashboard() {
  const { user, switchRole } = useAuth();
  if (!user) return null;

  let dashboard;
  switch (String(user.role)) {
    case 'admin': dashboard = <AdminDashboard />; break;
    case 'practitioner': dashboard = <PractitionerDashboard />; break;
    case 'nurse':
    case 'midwife':
    case 'specialist_nurse': dashboard = <NurseDashboard />; break;
    case 'lab_technician': dashboard = <LabTechDashboard />; break;
    case 'radiologist': dashboard = <RadiologistDashboard />; break;
    case 'radiology_technician': dashboard = <RadiologyTechnicianDashboard />; break;
    case 'pharmacist': dashboard = <PharmacyDashboard />; break;
    case 'accountant': dashboard = <AccountsDashboard />; break;
    case 'canteen': dashboard = <CanteenDashboard />; break;
    case 'patient': dashboard = <PatientDashboard />; break;
    case 'it_admin': dashboard = <ITAdminDashboard />; break;
    case 'front_desk': dashboard = <FrontDeskDashboard />; break;
    default:
      dashboard = (
        <div className="rounded-2xl border border-warning/30 bg-warning/5 p-5" role="alert">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-warning" aria-hidden="true" />
            <div>
              <p className="font-semibold">Dashboard unavailable</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Your account has an unsupported role configuration. No role-specific workspace has been granted.
              </p>
            </div>
          </div>
        </div>
      );
  }

  const showReferral = ['practitioner', 'nurse', 'midwife', 'specialist_nurse'].includes(user.role);
  const showSettlement = ['admin', 'accountant'].includes(user.role);

  return (
    <div className="space-y-6">
      {user.roles.length > 1 && (
        <section
          aria-label="Active operational role"
          className="flex flex-col gap-2 rounded-2xl border border-border bg-card/80 px-4 py-3 shadow-sm sm:flex-row sm:items-center sm:justify-between"
        >
          <div className="min-w-0">
            <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-primary">Active role</p>
            <p className="text-xs text-muted-foreground">
              Dashboard content, navigation and server-authorized workspace data follow this role.
            </p>
          </div>
          <label className="relative inline-flex shrink-0 items-center rounded-xl border border-border bg-background px-3 py-2 text-sm font-medium focus-within:ring-2 focus-within:ring-ring">
            <span className="sr-only">Select active operational role</span>
            <select
              aria-label="Active operational role"
              value={user.role}
              onChange={(event) => switchRole(event.target.value as UserRole)}
              className="appearance-none bg-transparent pr-7 font-medium capitalize outline-none"
            >
              {user.roles.map((role) => (
                <option key={role} value={role}>{role.replace(/_/g, ' ')}</option>
              ))}
            </select>
            <ChevronDown className="pointer-events-none absolute right-2.5 h-4 w-4 text-muted-foreground" aria-hidden="true" />
          </label>
        </section>
      )}

      {showReferral && (
        <section aria-label="Specialist referrals">
          <SpecialistReferralCard />
        </section>
      )}

      {showSettlement && (
        <section aria-label="Financial settlement">
          <FinancialSettlementCard />
        </section>
      )}

      {dashboard}
    </div>
  );
}
