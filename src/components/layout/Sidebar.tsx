import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { cn } from '@/lib/utils';
import {
  LayoutDashboard,
  Users,
  Calendar,
  FileText,
  Stethoscope,
  FlaskConical,
  Pill,
  CreditCard,
  BedDouble,
  Baby,
  Utensils,
  Settings,
  Bell,
  LogOut,
  ChevronLeft,
  ChevronRight,
  Activity,
  UserCog,
  ClipboardList,
  Syringe,
  HeartPulse,
  Eye,
  ShieldCheck,
  MessageSquare,
  Database,
} from 'lucide-react';

interface NavItem {
  icon: React.ElementType;
  label: string;
  href: string;
  badge?: number;
}

const roleNavItems: Record<string, NavItem[]> = {
  admin: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Users, label: 'Patients', href: '/patients' },
    { icon: ClipboardList, label: 'Registration', href: '/registration' },
    { icon: Calendar, label: 'Appointments', href: '/appointments' },
    { icon: FileText, label: 'Medical Records', href: '/records' },
    { icon: FlaskConical, label: 'Lab Results', href: '/lab-results' },
    { icon: Pill, label: 'Medications', href: '/medications' },
    { icon: CreditCard, label: 'Insurance', href: '/insurance' },
    { icon: FileText, label: 'Public Health', href: '/public-health' },
    { icon: Activity, label: 'Roster Generator', href: '/roster' },
    { icon: ShieldCheck, label: 'AI Hub', href: '/ai-clinical' },
    { icon: Database, label: 'System Administration', href: '/admin/system' },
    { icon: Bell, label: 'Notifications', href: '/notifications', badge: 5 },
  ],
  front_desk: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Users, label: 'Patients', href: '/patients' },
    { icon: Calendar, label: 'Appointments', href: '/appointments' },
    { icon: ClipboardList, label: 'Registration', href: '/registration' },
    { icon: HeartPulse, label: 'Triage', href: '/vitals' },
    { icon: Bell, label: 'Notifications', href: '/notifications', badge: 3 },
  ],
  practitioner: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Calendar, label: 'Appointments', href: '/appointments' },
    { icon: Users, label: 'My Patients', href: '/patients' },
    { icon: Stethoscope, label: 'Consultation', href: '/consultation' },
    { icon: FileText, label: 'Medical Records', href: '/records' },
    { icon: FlaskConical, label: 'Lab Results', href: '/lab-results', badge: 2 },
    { icon: Eye, label: 'Ophthalmology', href: '/ophthalmology' },
    { icon: MessageSquare, label: 'Patient Chat', href: '/patients' },
    { icon: ShieldCheck, label: 'AI Hub', href: '/ai-clinical' },
    { icon: Bell, label: 'Notifications', href: '/notifications', badge: 4 },
  ],
  nurse: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Users, label: 'Patients', href: '/patients' },
    { icon: BedDouble, label: 'Inpatients', href: '/inpatients' },
    { icon: HeartPulse, label: 'Vitals', href: '/vitals' },
    { icon: Syringe, label: 'Medications', href: '/medications' },
    { icon: FileText, label: 'Nursing Notes', href: '/nursing-notes' },
    { icon: MessageSquare, label: 'Patient Chat', href: '/patients' },
    { icon: Bell, label: 'Notifications', href: '/notifications', badge: 6 },
  ],
  midwife: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Baby, label: 'Maternity', href: '/maternity' },
    { icon: BedDouble, label: 'Admissions', href: '/admissions' },
    { icon: HeartPulse, label: 'Monitoring', href: '/monitoring' },
    { icon: MessageSquare, label: 'Patient Chat', href: '/patients' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  lab_technician: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: FlaskConical, label: 'Lab Requests', href: '/lab-requests', badge: 8 },
    { icon: FileText, label: 'Results Entry', href: '/results-entry' },
    { icon: ClipboardList, label: 'Reports', href: '/reports' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  pharmacist: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Pill, label: 'Dispensing', href: '/dispensing', badge: 12 },
    { icon: ClipboardList, label: 'Inventory', href: '/inventory' },
    { icon: FileText, label: 'Stock Alerts', href: '/stock-alerts', badge: 3 },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  accountant: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: CreditCard, label: 'Billing', href: '/billing' },
    { icon: FileText, label: 'Invoices', href: '/invoices' },
    { icon: Users, label: 'Insurance', href: '/insurance' },
    { icon: ClipboardList, label: 'Reports', href: '/financial-reports' },
    { icon: FileText, label: 'Public Health', href: '/public-health' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  canteen: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Utensils, label: 'Menu', href: '/menu' },
    { icon: ClipboardList, label: 'Orders', href: '/orders', badge: 5 },
    { icon: Users, label: 'Dietary Plans', href: '/dietary-plans' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  patient: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: FileText, label: 'Patient Portal', href: '/patient-portal' },
    { icon: Calendar, label: 'Appointments', href: '/appointments' },
    { icon: FileText, label: 'Medical Records', href: '/records' },
    { icon: CreditCard, label: 'Billing', href: '/billing' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
};

export default function Sidebar() {
  const [collapsed, setCollapsed] = useState(false);
  const { user, logout } = useAuth();
  const location = useLocation();

  if (!user) return null;

  const navItems = roleNavItems[user.role] || roleNavItems.front_desk;

  return (
    <aside
      className={cn(
        'fixed left-0 top-0 z-40 h-screen sidebar-gradient transition-all duration-300 flex flex-col',
        collapsed ? 'w-20' : 'w-64'
      )}
    >
      {/* Logo */}
      <div className="flex items-center justify-between p-4 border-b border-sidebar-border">
        {!collapsed && (
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-sidebar-primary flex items-center justify-center">
              <HeartPulse className="w-6 h-6 text-sidebar-primary-foreground" />
            </div>
            <div>
              <h1 className="font-heading font-bold text-sidebar-foreground text-lg">MediCare</h1>
              <p className="text-xs text-sidebar-foreground/60">Pro Health System</p>
            </div>
          </div>
        )}
        {collapsed && (
          <div className="w-10 h-10 rounded-xl bg-sidebar-primary flex items-center justify-center mx-auto">
            <HeartPulse className="w-6 h-6 text-sidebar-primary-foreground" />
          </div>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 p-3 overflow-y-auto">
        <ul className="space-y-1">
          {navItems.map((item) => {
            const isActive = location.pathname === item.href;
            return (
              <li key={item.href}>
                <Link
                  to={item.href}
                  className={cn(
                    isActive ? 'nav-link-active' : 'nav-link',
                    collapsed && 'justify-center px-2'
                  )}
                >
                  <div className="relative">
                    <item.icon className="w-5 h-5 flex-shrink-0" />
                    {item.badge && item.badge > 0 && (
                      <span className="notification-dot" />
                    )}
                  </div>
                  {!collapsed && (
                    <>
                      <span className="flex-1">{item.label}</span>
                      {item.badge && item.badge > 0 && (
                        <span className="bg-critical text-critical-foreground text-xs font-medium px-2 py-0.5 rounded-full">
                          {item.badge}
                        </span>
                      )}
                    </>
                  )}
                </Link>
              </li>
            );
          })}
        </ul>

        {/* Fertility Clinic Section */}
        {(user.role === 'admin' || user.role === 'practitioner' || user.role === 'nurse') && (
          <div className="mt-6 pt-6 border-t border-sidebar-border">
            {!collapsed && (
              <p className="px-3 text-xs font-medium text-sidebar-foreground/50 uppercase tracking-wider mb-2">
                Fertility Clinic
              </p>
            )}
            <Link
              to="/fertility"
              className={cn(
                location.pathname.startsWith('/fertility') ? 'nav-link-active' : 'nav-link',
                collapsed && 'justify-center px-2',
                'bg-fertility/10 hover:bg-fertility/20'
              )}
            >
              <Baby className="w-5 h-5 flex-shrink-0 text-fertility" />
              {!collapsed && <span className="text-fertility">Fertility Services</span>}
            </Link>
          </div>
        )}
      </nav>

      {/* User Section */}
      <div className="p-3 border-t border-sidebar-border">
        {!collapsed && (
          <div className="flex items-center gap-3 px-3 py-2 mb-2">
            <div className="w-9 h-9 rounded-full bg-sidebar-accent flex items-center justify-center text-sidebar-foreground font-medium">
              {user.firstName[0]}{user.lastName[0]}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-sidebar-foreground truncate">
                {user.firstName} {user.lastName}
              </p>
              <p className="text-xs text-sidebar-foreground/60 capitalize truncate">
                {user.role.replace('_', ' ')}
              </p>
            </div>
          </div>
        )}
        <button
          onClick={logout}
          className={cn(
            'nav-link w-full text-critical hover:text-critical hover:bg-critical/10',
            collapsed && 'justify-center px-2'
          )}
        >
          <LogOut className="w-5 h-5" />
          {!collapsed && <span>Sign Out</span>}
        </button>
      </div>

      {/* Collapse Toggle */}
      <button
        onClick={() => setCollapsed(!collapsed)}
        className="absolute -right-3 top-20 w-6 h-6 rounded-full bg-card border border-border shadow-md flex items-center justify-center text-muted-foreground hover:text-foreground transition-colors"
      >
        {collapsed ? (
          <ChevronRight className="w-4 h-4" />
        ) : (
          <ChevronLeft className="w-4 h-4" />
        )}
      </button>
    </aside>
  );
}
