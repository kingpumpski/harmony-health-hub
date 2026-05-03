import { useState, useEffect } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import MedicalLogo from '@/components/MedicalLogo';
import {
  LayoutDashboard, Users, Calendar, FileText, Stethoscope, FlaskConical,
  Pill, CreditCard, BedDouble, Baby, Utensils, Bell, LogOut,
  ChevronLeft, ChevronRight, Activity, ClipboardList, Syringe, HeartPulse,
  Eye, ShieldCheck, MessageSquare, Database, Video, Receipt, UserCog,
  Smile, Scissors, Sparkles, Upload, BookOpen, FileSearch, Bot,
} from 'lucide-react';

interface NavItem { icon: React.ElementType; label: string; href: string }

const roleNavItems: Record<string, NavItem[]> = {
  admin: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Users, label: 'Patients', href: '/patients' },
    { icon: ClipboardList, label: 'Registration', href: '/registration' },
    { icon: Calendar, label: 'Appointments', href: '/appointments' },
    { icon: HeartPulse, label: 'Triage', href: '/vitals' },
    { icon: Stethoscope, label: 'Encounters', href: '/encounters' },
    { icon: Smile, label: 'Dental', href: '/dental' },
    { icon: Scissors, label: 'Procedures', href: '/procedures' },
    { icon: Activity, label: 'Anesthesia', href: '/anesthesia' },
    { icon: BookOpen, label: 'Treatment Templates', href: '/treatment-templates' },
    { icon: FlaskConical, label: 'Laboratory', href: '/laboratory' },
    { icon: Upload, label: 'Outside Lab Uploads', href: '/outside-lab' },
    { icon: Pill, label: 'Pharmacy', href: '/pharmacy' },
    { icon: CreditCard, label: 'Billing', href: '/billing' },
    { icon: Video, label: 'Telemedicine', href: '/telemedicine' },
    { icon: Baby, label: 'Fertility', href: '/fertility' },
    { icon: Utensils, label: 'Canteen', href: '/menu' },
    { icon: Sparkles, label: 'AI Report', href: '/ai-report' },
    { icon: ShieldCheck, label: 'AI Hub', href: '/ai-clinical' },
    { icon: UserCog, label: 'Manage Users', href: '/admin/users' },
    { icon: Database, label: 'System Library', href: '/admin/system' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  front_desk: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Users, label: 'Patients', href: '/patients' },
    { icon: ClipboardList, label: 'Registration', href: '/registration' },
    { icon: Calendar, label: 'Appointments', href: '/appointments' },
    { icon: HeartPulse, label: 'Triage', href: '/vitals' },
    { icon: CreditCard, label: 'Billing', href: '/billing' },
    { icon: Bot, label: 'AI Assistant', href: '/ai-assistant' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  practitioner: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Calendar, label: 'Appointments', href: '/appointments' },
    { icon: Users, label: 'Patients', href: '/patients' },
    { icon: Stethoscope, label: 'Encounters', href: '/encounters' },
    { icon: Smile, label: 'Dental', href: '/dental' },
    { icon: Scissors, label: 'Procedure Notes', href: '/procedures' },
    { icon: Activity, label: 'Anesthesia', href: '/anesthesia' },
    { icon: BookOpen, label: 'Treatment Templates', href: '/treatment-templates' },
    { icon: FlaskConical, label: 'Lab Results', href: '/laboratory' },
    { icon: Upload, label: 'Outside Lab Uploads', href: '/outside-lab' },
    { icon: Pill, label: 'Prescriptions', href: '/pharmacy' },
    { icon: Video, label: 'Telemedicine', href: '/telemedicine' },
    { icon: Baby, label: 'Fertility', href: '/fertility' },
    { icon: Eye, label: 'Ophthalmology', href: '/ophthalmology' },
    { icon: Sparkles, label: 'AI Report', href: '/ai-report' },
    { icon: ShieldCheck, label: 'AI Hub', href: '/ai-clinical' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  nurse: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Users, label: 'Patients', href: '/patients' },
    { icon: HeartPulse, label: 'Vitals & Triage', href: '/vitals' },
    { icon: Stethoscope, label: 'Encounters', href: '/encounters' },
    { icon: BedDouble, label: 'Inpatients', href: '/inpatients' },
    { icon: Syringe, label: 'Medications', href: '/pharmacy' },
    { icon: Utensils, label: 'Meal Orders', href: '/menu' },
    { icon: Bot, label: 'AI Assistant', href: '/ai-assistant' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  midwife: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Baby, label: 'Maternity', href: '/maternity' },
    { icon: Baby, label: 'Fertility', href: '/fertility' },
    { icon: BedDouble, label: 'Admissions', href: '/admissions' },
    { icon: HeartPulse, label: 'Vitals', href: '/vitals' },
    { icon: Bot, label: 'AI Assistant', href: '/ai-assistant' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  lab_technician: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: FlaskConical, label: 'Laboratory', href: '/laboratory' },
    { icon: Upload, label: 'Outside Lab Uploads', href: '/outside-lab' },
    { icon: ClipboardList, label: 'Reports', href: '/reports' },
    { icon: Bot, label: 'AI Assistant', href: '/ai-assistant' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  pharmacist: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Pill, label: 'Pharmacy / Dispensing', href: '/pharmacy' },
    { icon: ClipboardList, label: 'Inventory', href: '/inventory' },
    { icon: FileText, label: 'Stock Alerts', href: '/stock-alerts' },
    { icon: Bot, label: 'AI Assistant', href: '/ai-assistant' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  accountant: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: CreditCard, label: 'Billing', href: '/billing' },
    { icon: Receipt, label: 'Invoices', href: '/billing' },
    { icon: ShieldCheck, label: 'Insurance', href: '/billing' },
    { icon: ClipboardList, label: 'Financial Reports', href: '/financial-reports' },
    { icon: Bot, label: 'AI Assistant', href: '/ai-assistant' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  canteen: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: Utensils, label: 'Menu', href: '/menu' },
    { icon: ClipboardList, label: 'Orders', href: '/orders' },
    { icon: Users, label: 'Dietary Plans', href: '/dietary-plans' },
    { icon: Bot, label: 'AI Assistant', href: '/ai-assistant' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
  patient: [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/dashboard' },
    { icon: FileText, label: 'My Portal', href: '/patient-portal' },
    { icon: Calendar, label: 'My Appointments', href: '/appointments' },
    { icon: Video, label: 'My Telemedicine', href: '/telemedicine' },
    { icon: CreditCard, label: 'My Billing', href: '/billing' },
    { icon: Bell, label: 'Notifications', href: '/notifications' },
  ],
};

export default function Sidebar() {
  const [collapsed, setCollapsed] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);
  const { user, logout } = useAuth();
  const location = useLocation();

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const { count } = await supabase.from('notifications').select('id', { count: 'exact', head: true }).eq('is_read', false);
      setUnreadCount(count ?? 0);
    };
    load();
    const ch = supabase.channel('side-notif')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [user?.id]);

  if (!user) return null;
  const navItems = roleNavItems[user.role] || roleNavItems.patient;

  return (
    <aside
      className={cn(
        'fixed left-0 top-0 z-40 h-screen sidebar-gradient transition-all duration-300 flex flex-col',
        collapsed ? 'w-20' : 'w-64',
      )}
    >
      <div className="flex items-center justify-between p-4 border-b border-sidebar-border">
        {!collapsed ? (
          <MedicalLogo size="md" variant="sidebar" />
        ) : (
          <MedicalLogo size="sm" variant="sidebar" showText={false} />
        )}
      </div>

      <nav className="flex-1 p-3 overflow-y-auto">
        <ul className="space-y-1">
          {navItems.map((item) => {
            const isActive = location.pathname === item.href;
            const isNotif = item.href === '/notifications';
            return (
              <li key={item.label + item.href}>
                <Link
                  to={item.href}
                  className={cn(isActive ? 'nav-link-active' : 'nav-link', collapsed && 'justify-center px-2')}
                >
                  <div className="relative">
                    <item.icon className="w-5 h-5 flex-shrink-0" />
                    {isNotif && unreadCount > 0 && <span className="notification-dot" />}
                  </div>
                  {!collapsed && (
                    <>
                      <span className="flex-1">{item.label}</span>
                      {isNotif && unreadCount > 0 && (
                        <span className="bg-critical text-critical-foreground text-xs font-medium px-2 py-0.5 rounded-full">
                          {unreadCount > 9 ? '9+' : unreadCount}
                        </span>
                      )}
                    </>
                  )}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      <div className="p-3 border-t border-sidebar-border">
        {!collapsed && (
          <div className="flex items-center gap-3 px-3 py-2 mb-2">
            <div className="w-9 h-9 rounded-full bg-sidebar-accent flex items-center justify-center text-sidebar-foreground font-medium">
              {(user.firstName?.[0] || user.email[0]).toUpperCase()}{(user.lastName?.[0] || '').toUpperCase()}
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
          className={cn('nav-link w-full text-critical hover:text-critical hover:bg-critical/10', collapsed && 'justify-center px-2')}
        >
          <LogOut className="w-5 h-5" />
          {!collapsed && <span>Sign Out</span>}
        </button>
      </div>

      <button
        onClick={() => setCollapsed(!collapsed)}
        className="absolute -right-3 top-20 w-6 h-6 rounded-full bg-card border border-border shadow-md flex items-center justify-center text-muted-foreground hover:text-foreground transition-colors"
      >
        {collapsed ? <ChevronRight className="w-4 h-4" /> : <ChevronLeft className="w-4 h-4" />}
      </button>
    </aside>
  );
}
