import type { ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import type { UserRole } from '@/types';

interface RoleGuardProps {
  allowedRoles: readonly UserRole[];
  children: ReactNode;
}

export default function RoleGuard({ allowedRoles, children }: RoleGuardProps) {
  const { user, loading, isAuthenticated } = useAuth();
  const location = useLocation();

  if (loading) {
    return <div className="flex min-h-[40vh] items-center justify-center p-12 text-sm text-muted-foreground">Checking access…</div>;
  }

  if (!isAuthenticated || !user) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }

  if (!user.roles.includes('admin') && !allowedRoles.includes(user.role)) {
    return (
      <div className="mx-auto flex min-h-[50vh] max-w-xl items-center justify-center p-6">
        <section className="w-full rounded-2xl border bg-card p-6 text-center shadow-sm">
          <h1 className="text-xl font-semibold">Access restricted</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Your current role ({user.role.replaceAll('_', ' ')}) is not authorized to use this clinical workflow.
          </p>
          <p className="mt-2 text-xs text-muted-foreground">
            Access is enforced by the database as well; this page is hidden here to prevent unauthorized API requests.
          </p>
          <button type="button" className="btn-primary mt-5" onClick={() => window.history.back()}>
            Go back
          </button>
        </section>
      </div>
    );
  }

  return <>{children}</>;
}
