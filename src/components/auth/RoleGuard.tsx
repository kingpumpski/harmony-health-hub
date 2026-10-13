import type { ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useEffect } from 'react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import type { UserRole } from '@/types';
import { isSpecialtyModuleAllowed, moduleForPath, normalizeSpecialty, resolveUserSpecialty } from '@/config/specialtyModules';

interface RoleGuardProps {
  allowedRoles: readonly UserRole[];
  children: ReactNode;
}

export default function RoleGuard({ allowedRoles, children }: RoleGuardProps) {
  const { user, loading, isAuthenticated } = useAuth();
  const location = useLocation();
  const specialty = user ? resolveUserSpecialty(user.role, user.specialization) : null;
  const module = moduleForPath(location.pathname);
  const hasFullAdministrativeAccess = user?.role === 'admin' || user?.role === 'it_admin' || user?.role === 'system_superuser';
  const requestedSpecialtyValue = new URLSearchParams(location.search).get('specialty');
  const requestedSpecialty = normalizeSpecialty(requestedSpecialtyValue);
  const specialtyDenied = Boolean(
    !hasFullAdministrativeAccess &&
    ((module && !isSpecialtyModuleAllowed(specialty, module)) ||
      (requestedSpecialtyValue && (!requestedSpecialty || specialty !== requestedSpecialty))),
  );

  useEffect(() => {
    if (specialtyDenied) toast.error('Access Denied: You do not have permission to view this module.');
  }, [location.pathname, specialtyDenied]);

  if (loading) {
    return <div className="flex min-h-[40vh] items-center justify-center p-12 text-sm text-muted-foreground">Checking access…</div>;
  }

  if (!isAuthenticated || !user) {
    if (import.meta.env.DEV) console.debug('[auth] guard:redirect', location.pathname);
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }

  if (!allowedRoles.includes(user.role) && !hasFullAdministrativeAccess) {
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

  if (specialtyDenied) return <Navigate to="/dashboard" replace />;

  if (import.meta.env.DEV) console.debug('[auth] guard:allow', location.pathname, user.role);
  return <>{children}</>;
}
