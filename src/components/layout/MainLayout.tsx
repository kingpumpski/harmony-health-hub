import { useState } from 'react';
import { Outlet, Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import Sidebar from './Sidebar';
import Header from './Header';
import CriticalAlertOverlay from '@/components/CriticalAlertOverlay';
import EncounterWorkflowOverlay from '@/components/EncounterWorkflowOverlay';

const itAdminAllowedPaths = new Set([
  '/dashboard',
  '/profile',
  '/it-support',
  '/admin/logs',
  '/admin/offline-sync',
  '/notifications',
]);

export default function MainLayout() {
  const { user, isAuthenticated, loading } = useAuth();
  const location = useLocation();
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center bg-background"><div className="animate-pulse text-muted-foreground">Loading…</div></div>;
  }

  if (!isAuthenticated || !user) return <Navigate to="/login" replace />;

  if (user.role === 'it_admin' && !itAdminAllowedPaths.has(location.pathname)) {
    return <Navigate to="/it-support" replace />;
  }

  return (
    <div className="min-h-screen bg-background">
      <Sidebar collapsed={sidebarCollapsed} onToggle={() => setSidebarCollapsed(v => !v)} />
      <div className={`min-w-0 pl-20 transition-[padding] duration-300 ${sidebarCollapsed ? 'md:pl-20' : 'md:pl-64'}`}>
        <Header />
        <main className="min-w-0 p-4 sm:p-6 animate-fade-in">
          {user.role !== 'it_admin' && <EncounterWorkflowOverlay />}
          <Outlet />
        </main>
      </div>
      {user.role !== 'it_admin' && <CriticalAlertOverlay />}
    </div>
  );
}
