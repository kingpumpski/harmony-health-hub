import { useState } from 'react';
import { cn } from '@/lib/utils';
import { Outlet, Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import Sidebar from './Sidebar';
import Header from './Header';
import CriticalAlertOverlay from '@/components/CriticalAlertOverlay';
import EncounterWorkflowOverlay from '@/components/EncounterWorkflowOverlay';

const itAdminAllowedPaths = new Set(['/dashboard', '/profile', '/it-support', '/admin/logs', '/admin/offline-sync', '/notifications']);

export default function MainLayout() {
  const { user, isAuthenticated, loading } = useAuth();
  const location = useLocation();
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  if (loading) return <div className="flex min-h-screen items-center justify-center bg-background"><div className="flex items-center gap-3 text-sm text-muted-foreground"><div className="h-2 w-2 animate-pulse rounded-full bg-primary" />Loading Harmony Health Hub…</div></div>;
  if (!isAuthenticated || !user) return <Navigate to="/login" replace />;
  if (user.role === 'it_admin' && !itAdminAllowedPaths.has(location.pathname)) return <Navigate to="/it-support" replace />;

  return (
    <div className="min-h-screen bg-background">
      <Sidebar collapsed={sidebarCollapsed} onToggle={() => setSidebarCollapsed(v => !v)} mobileOpen={mobileNavOpen} onMobileClose={() => setMobileNavOpen(false)} />
      <div className={cn('min-w-0 transition-[padding] duration-300', sidebarCollapsed ? 'md:pl-20' : 'md:pl-64')}>
        <Header onMenu={() => setMobileNavOpen(true)} />
        <main className="min-w-0 px-3 py-4 sm:px-5 sm:py-6 lg:px-7 animate-fade-in">
          {user.role !== 'it_admin' && <EncounterWorkflowOverlay />}
          <Outlet />
        </main>
      </div>
      {user.role !== 'it_admin' && <CriticalAlertOverlay />}
    </div>
  );
}
