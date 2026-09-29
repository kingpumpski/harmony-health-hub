import { Activity, Clock3, ShieldCheck } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import WorkflowSummary from '@/components/WorkflowSummary';
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

export default function Dashboard(){
  const {user}=useAuth();
  if(!user)return null;
  let dashboard;
  switch(String(user.role)){
    case'admin':dashboard=<AdminDashboard/>;break;
    case'practitioner':dashboard=<PractitionerDashboard/>;break;
    case'nurse':case'midwife':case'specialist_nurse':dashboard=<NurseDashboard/>;break;
    case'lab_technician':dashboard=<LabTechDashboard/>;break;
    case'radiologist':dashboard=<RadiologistDashboard/>;break;
    case'radiology_technician':dashboard=<RadiologyTechnicianDashboard/>;break;
    case'pharmacist':dashboard=<PharmacyDashboard/>;break;
    case'accountant':dashboard=<AccountsDashboard/>;break;
    case'canteen':dashboard=<CanteenDashboard/>;break;
    case'patient':dashboard=<PatientDashboard/>;break;
    case'it_admin':dashboard=<ITAdminDashboard/>;break;
    case'front_desk':dashboard=<FrontDeskDashboard/>;break;
    default:dashboard=<div className="rounded-2xl border border-warning/30 bg-warning/5 p-5"><div className="flex items-start gap-3"><AlertTriangle className="h-5 w-5 text-warning"/><div><p className="font-semibold">Dashboard unavailable</p><p className="mt-1 text-sm text-muted-foreground">Your account has an unsupported role configuration. No role-specific workspace has been granted.</p></div></div></div>;
  }
  const displayName=user.firstName || user.email.split('@')[0];
  const showReferral=['practitioner','nurse','midwife','specialist_nurse'].includes(user.role);
  const showSettlement=['admin','accountant'].includes(user.role);
  return <div className="space-y-1">
    <section className="mb-5 rounded-3xl border border-border bg-gradient-to-br from-card via-card to-primary/5 p-5 shadow-sm sm:p-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0">
          <p className="text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">Role command center</p>
          <h1 className="mt-1 text-xl font-heading font-bold tracking-tight sm:text-2xl">Good to see you, {displayName}</h1>
          <p className="mt-1 max-w-2xl text-sm text-muted-foreground">Your role-aware workspace is ready. Use the active cards and shortcuts to move directly into today's work.</p>
        </div>
        <div className="flex shrink-0 flex-wrap gap-2">
          {user.roles.length > 1 && <label className="inline-flex items-center gap-2 rounded-full border border-border bg-background/80 px-3 py-1.5 text-xs font-medium">
            <span className="text-muted-foreground">Role</span>
            <select aria-label="Active operational role" value={user.role} onChange={(event) => user.switchRole(event.target.value as UserRole)} className="bg-transparent font-medium outline-none">
              {user.roles.map((role) => <option key={role} value={role}>{role.replace(/_/g, ' ')}</option>)}
            </select>
          </label>}
          <span className="inline-flex items-center gap-2 rounded-full border border-border bg-background/80 px-3 py-1.5 text-xs font-medium"><Activity className="h-3.5 w-3.5 text-primary"/>Live workspace</span>
          <span className="inline-flex items-center gap-2 rounded-full border border-border bg-background/80 px-3 py-1.5 text-xs font-medium"><ShieldCheck className="h-3.5 w-3.5 text-success"/>Access controlled</span>
          <span className="hidden items-center gap-2 rounded-full border border-border bg-background/80 px-3 py-1.5 text-xs font-medium sm:inline-flex"><Clock3 className="h-3.5 w-3.5 text-muted-foreground"/>Today</span>
        </div>
      </div>
    </section>
    {showReferral && <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3"><SpecialistReferralCard/></div>}
    {showSettlement && <div className="mb-6"><FinancialSettlementCard/></div>}
    {dashboard}
    <WorkflowSummary/>
  </div>;
}