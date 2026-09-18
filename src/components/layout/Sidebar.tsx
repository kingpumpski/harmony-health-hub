import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { cn } from '@/lib/utils';
import { BarChart3, Calendar, ChevronLeft, ChevronRight, ClipboardList, CreditCard, FlaskConical, HeartPulse, LayoutDashboard, LogOut, Pill, ShieldCheck, Stethoscope, Users, BedDouble, Settings, FileText } from 'lucide-react';
import { getDefaultPermissions, type Permission } from '@/lib/permissions';

interface NavItem { icon: React.ElementType; label: string; href: string; permission: Permission }
interface SidebarProps { collapsed: boolean; onToggle: () => void }

const domain = (icon: React.ElementType, label: string, href: string, permission: Permission): NavItem => ({ icon, label, href, permission });

const roleNavItems: Record<string, NavItem[]> = {
  admin: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(Users,'Patients','/patients','patients'),
    domain(Calendar,'Appointments','/appointments','appointments'), domain(Stethoscope,'Clinical Operations','/clinical-operations','clinical_operations'),
    domain(BedDouble,'Inpatient','/inpatient','inpatient'), domain(Pill,'Pharmacy','/pharmacy','pharmacy'),
    domain(FlaskConical,'Laboratory','/laboratory','laboratory'), domain(BarChart3,'Reports Center','/reports','reports'),
    domain(CreditCard,'Finance','/finance','finance'), domain(Settings,'Administration','/administration','administration'),
  ],
  practitioner: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(Users,'Patients','/patients','patients'),
    domain(Calendar,'Appointments','/appointments','appointments'), domain(Stethoscope,'Clinical Operations','/clinical-operations','clinical_operations'),
    domain(BedDouble,'Inpatient','/inpatient','inpatient'), domain(FlaskConical,'Laboratory Results','/clinical-results','radiology_results'),
    domain(BarChart3,'Reports Center','/reports','reports'),
  ],
  nurse: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(Users,'Patients','/patients','patients'),
    domain(Stethoscope,'Clinical Operations','/clinical-operations','clinical_operations'), domain(BedDouble,'Inpatient','/inpatient','inpatient'),
    domain(FlaskConical,'Laboratory Results','/clinical-results','radiology_results'),
  ],
  specialist_nurse: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(Users,'Patients','/patients','patients'),
    domain(Calendar,'Appointments','/appointments','appointments'), domain(Stethoscope,'Clinical Operations','/clinical-operations','clinical_operations'),
    domain(BedDouble,'Inpatient','/inpatient','inpatient'), domain(FlaskConical,'Laboratory Results','/clinical-results','radiology_results'),
  ],
  midwife: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(Users,'Patients','/patients','patients'),
    domain(Stethoscope,'Clinical Operations','/clinical-operations','clinical_operations'), domain(BedDouble,'Inpatient','/inpatient','inpatient'),
  ],
  front_desk: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(Users,'Patients','/patients','patients'),
    domain(Calendar,'Appointments','/appointments','appointments'), domain(CreditCard,'Finance','/finance','finance'),
  ],
  pharmacist: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(Pill,'Pharmacy','/pharmacy','pharmacy'),
  ],
  lab_technician: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(FlaskConical,'Laboratory','/laboratory','laboratory'),
    domain(BarChart3,'Reports Center','/reports','reports'),
  ],
  accountant: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(CreditCard,'Finance','/finance','finance'),
    domain(BarChart3,'Reports Center','/reports','reports'),
  ],
  radiologist: [
    domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(FlaskConical,'Laboratory Results','/clinical-results','radiology_results'),
    domain(Users,'Patients','/patients','patients'),
  ],
  canteen: [domain(LayoutDashboard,'Dashboard','/dashboard','dashboard')],
  patient: [domain(LayoutDashboard,'Dashboard','/dashboard','dashboard'), domain(FileText,'My Portal','/patient-portal','patient_portal'), domain(Calendar,'My Appointments','/appointments','appointments')],
};

export default function Sidebar({ collapsed, onToggle }: SidebarProps) {
  const { user, logout } = useAuth();
  const location = useLocation();
  if (!user) return null;
  const permissions = new Set(user.permissions?.length ? user.permissions : getDefaultPermissions(user.role));
  const items = (roleNavItems[user.role] ?? roleNavItems.patient).filter(item => permissions.has(item.permission));
  return <aside className={cn('fixed left-0 top-0 z-40 flex h-screen flex-col sidebar-gradient transition-[width] duration-300 max-md:w-20', collapsed ? 'w-20' : 'w-64')}>
    <div className="flex items-center justify-between border-b border-sidebar-border p-4">
      {!collapsed && <div className="flex min-w-0 items-center gap-3"><div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-sidebar-primary"><HeartPulse className="h-6 w-6 text-sidebar-primary-foreground" /></div><div className="min-w-0"><h1 className="font-heading text-lg font-bold text-sidebar-foreground">Harmony Health Hub</h1><p className="truncate text-xs text-sidebar-foreground/60">Healthcare Management System</p></div></div>}
      {collapsed && <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-xl bg-sidebar-primary"><HeartPulse className="h-6 w-6 text-sidebar-primary-foreground" /></div>}
      <button type="button" onClick={onToggle} className="rounded-md p-1 text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground" aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}>{collapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}</button>
    </div>
    <nav className="flex-1 overflow-y-auto p-3"><ul className="space-y-1">{items.map(item => { const active = location.pathname === item.href || location.pathname.startsWith(item.href + '/'); return <li key={item.href}><Link to={item.href} title={collapsed ? item.label : undefined} className={cn(active ? 'nav-link-active' : 'nav-link', collapsed && 'justify-center px-2')}><item.icon className="h-5 w-5 shrink-0" />{!collapsed && <span className="min-w-0 flex-1 truncate">{item.label}</span>}</Link></li>; })}</ul></nav>
    <div className="border-t border-sidebar-border p-3">
      {!collapsed && <div className="mb-2 flex min-w-0 items-center gap-3 px-3 py-2"><div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-sidebar-accent font-medium text-sidebar-foreground">{(user.firstName?.[0] || user.email[0]).toUpperCase()}{(user.lastName?.[0] || '').toUpperCase()}</div><div className="min-w-0 flex-1"><p className="truncate text-sm font-medium text-sidebar-foreground">{user.firstName} {user.lastName}</p><p className="truncate text-xs capitalize text-sidebar-foreground/60">{user.role}</p></div></div>}
      <button type="button" onClick={() => void logout()} title="Sign out" className={cn('nav-link w-full', collapsed && 'justify-center px-2')}><LogOut className="h-5 w-5 shrink-0" />{!collapsed && <span>Sign out</span>}</button>
    </div>
  </aside>;
}