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
    case 'nurse': case 'midwife': case 'specialist_nurse': dashboard = <NurseDashboard />; break;
    case 'lab_technician': dashboard = <LabTechDashboard />; break;
    case 'radiologist': dashboard = <RadiologistDashboard />; break;
    case 'radiology_technician': dashboard = <RadiologyTechnicianDashboard />; break;
    case 'pharmacist': dashboard = <PharmacyDashboard />; break;
    case 'accountant': dashboard = <AccountsDashboard />; break;
    case 'canteen': dashboard = <CanteenDashboard />; break;
    case 'patient': dashboard = <PatientDashboard />; break;
    case 'it_admin': dashboard = <ITAdminDashboard />; break;
    case 'front_desk': dashboard = <FrontDeskDashboard />; break;
    default: dashboard = <div className="rounded-2xl border border-warning/30 bg-warning/5 p-5"><div className="flex items-start gap-3"><AlertTriangle className="h-5 w-5 text-warning" /><div><p className="font-semibold">Dashboard unavailable</p><p className="mt-1 text-sm text-muted-foreground">Your account has an unsupported role configuration. No role-specific workspace has been granted.</p></div></div></div>;
  }
  const showReferral = ['practitioner','nurse','midwife','specialist_nurse'].includes(user.role);
  const showSettlement = ['admin','accountant'].includes(user.role);
  return <div className="space-y-1">
    {user.roles.length > 1 && <div className="mb-4 flex justify-end"><label className="inline-flex items-center gap-2 rounded-full border border-border bg-background px-3 py-1.5 text-xs font-medium"><span className="sr-only">Active operational role</span><select aria-label="Active operational role" value={user.role} onChange={(event) => switchRole(event.target.value as UserRole)} className="bg-transparent font-medium outline-none">{user.roles.map(role => <option key={role} value={role}>{role.replace(/_/g, ' ')}</option>)}</select></label></div>}
    {showReferral && <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3"><SpecialistReferralCard /></div>}
    {showSettlement && <div className="mb-6"><FinancialSettlementCard /></div>}
    {dashboard}
  </div>;
}