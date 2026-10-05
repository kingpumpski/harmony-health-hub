import { useEffect, useState } from 'react';
import { cn } from '@/lib/utils';
import { Outlet, Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import Sidebar from './Sidebar';
import Header from './Header';
import CriticalAlertOverlay from '@/components/CriticalAlertOverlay';
import EncounterWorkflowOverlay from '@/components/EncounterWorkflowOverlay';
import RouteLoadingScreen from '@/components/system/RouteLoadingScreen';

export default function MainLayout() {
  const { user, isAuthenticated, loading } = useAuth();
  const location = useLocation();
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  // Close the mobile drawer after navigation so it never obscures the destination page.
  useEffect(() => {
    setMobileNavOpen(false);
  }, [location.pathname]);

  if (loading) return <RouteLoadingScreen />;
  if (!isAuthenticated || !user) return <Navigate to="/login" replace />;

  return (
    <div className="min-h-screen bg-background">
      <a
        href="#main-content"
        className="sr-only z-[100] rounded-md bg-primary px-4 py-2 font-medium text-primary-foreground focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
      >
        Skip to main content
      </a>
      <Sidebar collapsed={sidebarCollapsed} onToggle={() => setSidebarCollapsed(v => !v)} mobileOpen={mobileNavOpen} onMobileClose={() => setMobileNavOpen(false)} />
      <div className={cn('min-w-0 transition-[padding] duration-300 motion-reduce:transition-none', sidebarCollapsed ? 'md:pl-20' : 'md:pl-64')}>
        <Header onMenu={() => setMobileNavOpen(true)} />
        <main id="main-content" tabIndex={-1} className="min-w-0 px-3 py-4 outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring sm:px-5 sm:py-6 lg:px-7 animate-fade-in motion-reduce:animate-none">
          {user.role !== 'it_admin' && <EncounterWorkflowOverlay />}
          <Outlet />
        </main>
      </div>
      {user.role !== 'it_admin' && <CriticalAlertOverlay />}
    </div>
  );
}
