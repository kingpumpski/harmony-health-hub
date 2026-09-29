import { useEffect, useState } from 'react';
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
  const [showGreeting, setShowGreeting] = useState(true);

  useEffect(() => {
    if (!loading && isAuthenticated && user) {
      setShowGreeting(true);
      const timer = window.setTimeout(() => setShowGreeting(false), 2500);
      return () => window.clearTimeout(timer);
    }
    return undefined;
  }, [loading, isAuthenticated, user]);

  if (loading) return <div className="flex min-h-screen items-center justify-center bg-background"><div className="flex items-center gap-3 text-sm text-muted-foreground"><div className="h-2 w-2 animate-pulse rounded-full bg-primary" />Loading Harmony Health Hub…</div></div>;
  if (!isAuthenticated || !user) return <Navigate to="/login" replace />;
  if (user.role === 'it_admin' && !itAdminAllowedPaths.has(location.pathname)) return <Navigate to="/it-support" replace />;

  return <div className="min-h-screen bg-background">
    <Sidebar collapsed={sidebarCollapsed} onToggle={() => setSidebarCollapsed(v => !v)} mobileOpen={mobileNavOpen} onMobileClose={() => setMobileNavOpen(false)} />
    <div className={cn('min-w-0 transition-[padding] duration-300', sidebarCollapsed ? 'md:pl-20' : 'md:pl-64')}>
      <Header onMenu={() => setMobileNavOpen(true)} />
      {showGreeting && <div role="status" aria-live="polite" className="pointer-events-none fixed left-1/2 top-[4.5rem] z-20 -translate-x-1/2 rounded-full border border-primary/20 bg-card/95 px-4 py-2 text-sm font-medium text-foreground shadow-lg backdrop-blur">Welcome, {user.firstName || user.email.split('@')[0]}. Your workspace is ready.</div>}
      <main className="min-w-0 px-3 py-4 sm:px-5 sm:py-6 lg:px-7 animate-fade-in">{user.role !== 'it_admin' && <EncounterWorkflowOverlay />}<Outlet /></main>
    </div>
    {user.role !== 'it_admin' && <CriticalAlertOverlay />}
  </div>;
}
