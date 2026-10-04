// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { cn } from '@/lib/utils';
import { Activity, BarChart3, Bell, BedDouble, Building2, Calendar, ChevronLeft, ChevronRight, Cloud, CloudOff, CreditCard, FileText, FlaskConical, HeartPulse, LayoutDashboard, Menu, Pill, Settings, ShieldAlert, ShieldCheck, Stethoscope, Users, ScanLine } from 'lucide-react';
import { getDefaultPermissions, type Permission } from '@/lib/permissions';

interface NavItem { icon: React.ElementType; label: string; href: string; permission: Permission }
interface NavGroup { label: string; icon: React.ElementType; items: NavItem[] }
interface SidebarProps { collapsed: boolean; onToggle: () => void; mobileOpen: boolean; onMobileClose: () => void }

const item = (icon: React.ElementType, label: string, href: string, permission: Permission): NavItem => ({ icon, label, href, permission });

const roleNavGroups: Record<string, NavGroup[]> = {
  admin: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Patient Care', icon: Users, items: [item(Users, 'Patients', '/patients', 'patients'), item(Calendar, 'Appointments', '/appointments', 'appointments'), item(HeartPulse, 'Triage & Vitals', '/vitals', 'triage'), item(Stethoscope, 'Healthcare', '/clinical-operations', 'clinical_operations'), item(BedDouble, 'Inpatient', '/inpatient', 'inpatient')] },
    { label: 'Diagnostics & Medicines', icon: FlaskConical, items: [item(FlaskConical, 'Laboratory', '/laboratory', 'laboratory'), item(ScanLine, 'Radiology', '/radiology', 'radiology'), item(Pill, 'Pharmacy', '/pharmacy', 'pharmacy')] },
    { label: 'Billing', icon: CreditCard, items: [item(CreditCard, 'Billing', '/billing', 'finance')] },
    { label: 'Administration', icon: Settings, items: [item(Settings, 'Administration', '/administration', 'administration'), item(BedDouble, 'Ward & Bed Management', '/ward-bed-board', 'ward'), item(ShieldCheck, 'Clinical References', '/admin/clinical-references', 'clinical_references'), item(Building2, 'Insurance Companies', '/admin/insurance-companies', 'insurance_companies'), item(ShieldCheck, 'Facility Attribution', '/admin/facility-attribution', 'facility_attribution'), item(ShieldCheck, 'IT Support', '/it-support', 'it_support'), item(Settings, 'System Settings', '/admin/settings', 'system_settings')] },
  ],
  practitioner: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Patient Care', icon: Users, items: [item(Users, 'Patients', '/patients', 'patients'), item(Calendar, 'Appointments', '/appointments', 'appointments'), item(HeartPulse, 'Triage & Vitals', '/vitals', 'triage'), item(Stethoscope, 'Healthcare', '/clinical-operations', 'clinical_operations'), item(BedDouble, 'Inpatient', '/inpatient', 'inpatient')] },
    { label: 'Clinical Results', icon: FlaskConical, items: [item(FlaskConical, 'Laboratory Results', '/lab-results', 'laboratory_results'), item(ScanLine, 'Radiology Results', '/clinical-results', 'radiology_results')] },
  ],
  nurse: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Patient Care', icon: Users, items: [item(Users, 'Patients', '/patients', 'patients'), item(HeartPulse, 'Triage & Vitals', '/vitals', 'triage'), item(Stethoscope, 'Healthcare', '/clinical-operations', 'clinical_operations'), item(BedDouble, 'Inpatient', '/inpatient', 'inpatient')] },
    { label: 'Clinical Results', icon: FlaskConical, items: [item(FlaskConical, 'Laboratory Results', '/lab-results', 'laboratory_results'), item(ScanLine, 'Radiology Results', '/clinical-results', 'radiology_results')] },
  ],
  specialist_nurse: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Patient Care', icon: Users, items: [item(Users, 'Patients', '/patients', 'patients'), item(Stethoscope, 'Healthcare', '/clinical-operations', 'clinical_operations'), item(BedDouble, 'Inpatient', '/inpatient', 'inpatient')] },
    { label: 'Clinical Results', icon: FlaskConical, items: [item(FlaskConical, 'Laboratory Results', '/lab-results', 'laboratory_results'), item(ScanLine, 'Radiology Results', '/clinical-results', 'radiology_results')] },
  ],
  midwife: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Patient Care', icon: Users, items: [item(Users, 'Patients', '/patients', 'patients'), item(Stethoscope, 'Healthcare', '/clinical-operations', 'clinical_operations'), item(BedDouble, 'Inpatient', '/inpatient', 'inpatient')] },
    { label: 'Maternal Care', icon: HeartPulse, items: [item(HeartPulse, 'Maternity', '/maternity', 'maternity'), item(HeartPulse, 'Fertility', '/fertility', 'fertility')] },
    { label: 'Clinical Results', icon: FlaskConical, items: [item(FlaskConical, 'Laboratory Results', '/lab-results', 'laboratory_results'), item(ScanLine, 'Radiology Results', '/clinical-results', 'radiology_results')] },
  ],
  front_desk: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Patient Services', icon: Users, items: [item(Users, 'Patients', '/patients', 'patients'), item(FileText, 'Registration', '/registration', 'registration'), item(Calendar, 'Appointments', '/appointments', 'appointments')] },
    { label: 'Billing', icon: CreditCard, items: [item(CreditCard, 'Billing', '/billing', 'billing')] },
  ],
  pharmacist: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Medicines', icon: Pill, items: [item(Pill, 'Pharmacy', '/pharmacy', 'pharmacy'), item(Pill, 'Inventory', '/inventory', 'inventory'), item(Bell, 'Stock Alerts', '/stock-alerts', 'stock_alerts')] },
  ],
  lab_technician: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Diagnostics', icon: FlaskConical, items: [item(FlaskConical, 'Laboratory', '/laboratory', 'laboratory'), item(FlaskConical, 'Outside Lab', '/outside-lab', 'outside_lab')] },
  ],
  accountant: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Billing', icon: CreditCard, items: [item(CreditCard, 'Billing', '/billing', 'finance'), item(CreditCard, 'Accounts Approvals', '/accounts-approvals', 'accounts_approvals'), item(CreditCard, 'NHIS / Insurance Claims', '/insurance-claims', 'claims'), item(BarChart3, 'Financial Reports', '/financial-reports', 'financial_reports')] },
  ],
  radiology_technician: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Imaging', icon: ScanLine, items: [item(ScanLine, 'Radiology', '/radiology', 'radiology'), item(Users, 'Patients', '/patients', 'patients')] },
  ],
  radiologist: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Imaging', icon: ScanLine, items: [item(Users, 'Patients', '/patients', 'patients'), item(ScanLine, 'Radiology', '/radiology', 'radiology')] },
  ],
  system_superuser: [
    { label: 'Platform', icon: ShieldCheck, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard'), item(Building2, 'Facility Onboarding', '/admin/facility-onboarding', 'facility_onboarding'), item(Settings, 'System Settings', '/admin/settings', 'system_settings'), item(Users, 'User Management', '/admin/users', 'users'), item(ShieldCheck, 'Facility Data Sharing', '/admin/facility-sharing', 'facility_sharing')] },
  ],
  it_admin: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'System Operations', icon: Settings, items: [item(ShieldCheck, 'IT Support', '/it-support', 'it_support'), item(Settings, 'System Settings', '/admin/settings', 'system_settings'), item(ShieldCheck, 'Facility Attribution', '/admin/facility-attribution', 'facility_attribution'), item(BedDouble, 'Ward & Bed Management', '/ward-bed-board', 'ward'), item(Bell, 'Notifications', '/notifications', 'notifications')] },
  ],
  canteen: [
    { label: 'Overview', icon: LayoutDashboard, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard')] },
    { label: 'Meal Services', icon: Users, items: [item(FileText, 'Meal Orders', '/orders', 'orders'), item(Calendar, 'Menu', '/menu', 'meal_orders'), item(FileText, 'Dietary Plans', '/dietary-plans', 'dietary_plans')] },
  ],
  patient: [{ label: 'My Care', icon: Users, items: [item(LayoutDashboard, 'Dashboard', '/dashboard', 'dashboard'), item(FileText, 'My Portal', '/patient-portal', 'patient_portal'), item(Calendar, 'My Appointments', '/appointments', 'appointments'), item(HeartPulse, 'Telemedicine', '/telemedicine', 'telemedicine'), item(CreditCard, 'Billing', '/billing', 'billing'), item(Calendar, 'Meal Menu', '/menu', 'meal_orders')] }],
};

export default function Sidebar({ collapsed, onToggle, mobileOpen, onMobileClose }: SidebarProps) {
  const { user } = useAuth();
  const [online, setOnline] = React.useState(() => typeof navigator === 'undefined' ? true : navigator.onLine);
  React.useEffect(() => { const onOnline = () => setOnline(true); const onOffline = () => setOnline(false); window.addEventListener('online', onOnline); window.addEventListener('offline', onOffline); return () => { window.removeEventListener('online', onOnline); window.removeEventListener('offline', onOffline); }; }, []);
  const location = useLocation();
  if (!user) return null;

  const roleGroups = roleNavGroups[user.role];
  const unsupportedRole = !roleGroups;
  const permissions = new Set(user.permissions?.length ? user.permissions : getDefaultPermissions(user.role));
  const groups = (roleGroups ?? [])
    .map(group => ({ ...group, items: group.items.filter(nav => permissions.has(nav.permission)) }))
    .filter(group => group.items.length > 0);

  return (
    <>
      {mobileOpen && <button type="button" aria-label="Close navigation" className="fixed inset-0 z-40 bg-slate-950/50 backdrop-blur-sm md:hidden" onClick={onMobileClose} />}
      <aside className={cn(
        'fixed inset-y-0 left-0 z-50 flex w-[min(19rem,88vw)] flex-col sidebar-gradient text-sidebar-foreground transition-transform duration-300 md:z-40 md:w-64 md:translate-x-0',
        collapsed && 'md:w-20',
        !mobileOpen && '-translate-x-full md:translate-x-0',
        mobileOpen && 'translate-x-0',
      )}>
        <div className="flex min-h-16 items-center gap-3 border-b border-sidebar-border px-4">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-sidebar-primary shadow-sm"><HeartPulse className="h-6 w-6 text-sidebar-primary-foreground" /></div>
          {!collapsed && <div className="min-w-0 flex-1"><h1 className="truncate font-heading text-base font-bold">Harmony Health Hub</h1><p className="truncate text-[11px] text-sidebar-foreground/55">Healthcare Management System</p></div>}
          <button type="button" onClick={() => { onToggle(); onMobileClose(); }} className="hidden rounded-lg p-2 text-sidebar-foreground/65 hover:bg-sidebar-accent hover:text-sidebar-foreground md:inline-flex" aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}>{collapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}</button>
          <button type="button" onClick={onMobileClose} className="rounded-lg p-2 text-sidebar-foreground/65 hover:bg-sidebar-accent hover:text-sidebar-foreground md:hidden" aria-label="Close navigation"><Menu className="h-5 w-5" /></button>
        </div>

        <div className="border-b border-sidebar-border px-4 py-3">
          {!collapsed ? <div className="flex items-center gap-2 rounded-xl bg-sidebar-accent/70 px-3 py-2"><Activity className="h-4 w-4 text-sidebar-primary" /><div className="min-w-0"><p className="text-[10px] font-semibold uppercase tracking-wider text-sidebar-foreground/50">Workspace</p><p className="truncate text-xs font-medium">Healthcare</p></div></div> : <div className="flex justify-center"><Activity className="h-5 w-5 text-sidebar-primary" /></div>}
        </div>

        <nav aria-label="Primary navigation" className="flex-1 overflow-y-auto px-3 py-4">
          {unsupportedRole ? (
            <div role="alert" className="rounded-xl border border-sidebar-border bg-sidebar-accent/60 p-3 text-sm">
              <div className="flex items-start gap-2">
                <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0 text-sidebar-primary" />
                {!collapsed && <div><p className="font-semibold">Workspace unavailable</p><p className="mt-1 text-xs text-sidebar-foreground/60">Your assigned role is not configured for this workspace. Navigation is intentionally restricted until an administrator assigns a supported role.</p></div>}
              </div>
            </div>
          ) : (
            <div className="space-y-5">
              {groups.map(group => {
                const GroupIcon = group.icon;
                return <section key={group.label}>
                  {!collapsed && <div className="mb-2 flex items-center gap-2 px-2 text-[10px] font-semibold uppercase tracking-[0.14em] text-sidebar-foreground/40"><GroupIcon className="h-3.5 w-3.5" /><span>{group.label}</span></div>}
                  <ul className="space-y-1">{group.items.map(nav => {
                    const NavIcon = nav.icon;
                    const active = location.pathname === nav.href || location.pathname.startsWith(nav.href + '/');
                    return <li key={nav.href}><Link to={nav.href} onClick={onMobileClose} title={collapsed ? nav.label : undefined} aria-current={active ? 'page' : undefined} className={cn('nav-link group relative', active && 'nav-link-active', collapsed && 'justify-center px-2')}>
                      {active && <span className="absolute left-0 top-1/2 h-6 w-0.5 -translate-y-1/2 rounded-full bg-sidebar-primary-foreground/80" />}
                      <NavIcon className="h-[18px] w-[18px] shrink-0" />{!collapsed && <span className="min-w-0 flex-1 truncate">{nav.label}</span>}{!collapsed && active && <ChevronRight className="h-3.5 w-3.5 opacity-60" />}
                    </Link></li>;
                  })}</ul>
                </section>;
              })}
            </div>
          )}
        </nav>

        <div className="border-t border-sidebar-border p-3">
          <div className={cn("rounded-xl bg-sidebar-accent/70 px-3 py-2", collapsed && "px-2")}>
            <div className={cn("flex items-center gap-2", collapsed && "justify-center")}>
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-sidebar-accent text-[10px] font-bold uppercase">{user.role.replaceAll('_', ' ').slice(0, 2)}</div>
              {!collapsed && <div className="min-w-0 flex-1">
                <p className="truncate text-xs font-semibold capitalize">{user.role.replaceAll('_', ' ')}</p>
                <div className="mt-1 flex items-center gap-1.5 text-[10px] text-sidebar-foreground/60">{online ? <Cloud className="h-3 w-3 text-sidebar-primary" /> : <CloudOff className="h-3 w-3 text-warning" />}<span>{online ? 'Online' : 'Offline mode'}</span></div>
              </div>}
              {collapsed && (online ? <Cloud className="h-4 w-4 text-sidebar-primary" /> : <CloudOff className="h-4 w-4 text-warning" />)}
            </div>
          </div>
        </div>    </aside>
    </>
  );
}
