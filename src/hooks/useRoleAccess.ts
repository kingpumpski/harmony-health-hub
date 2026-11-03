import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';

const clinicalRoles = new Set([
  'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'lab_technician',
  'radiologist', 'radiology_technician', 'pharmacist', 'physiotherapist',
  'dentist', 'ophthalmologist', 'dietician',
]);

const financialPaths = new Set([
  '/billing', '/finance', '/invoices', '/insurance-claims', '/insurance',
  '/financial-reports', '/billing/tariffs', '/accounts-approvals',
]);

export function isFinancialNavigationPath(path: string): boolean {
  return financialPaths.has(path.split('?')[0]);
}

/**
 * UI visibility helper only. Route guards, RPC authorization and RLS remain
 * the security boundary; this hook must never be treated as authorization.
 */
export function useRoleAccess() {
  const { user } = useAuth();
  return useMemo(() => {
    const role = user?.role ?? null;
    const isAccountOfficer = role === 'accountant';
    const isAdmin = role === 'admin';
    const isITAdmin = role === 'it_admin';
    const isSystemSuperuser = role === 'system_superuser';
    const isPatient = role === 'patient';
    const isFrontDesk = role === 'front_desk';
    const isClinicalRole = role !== null && clinicalRoles.has(role);
    const canManageFinancialSettlement = isAccountOfficer;
    const canViewFinancialOverview = isAccountOfficer || isAdmin || isITAdmin || isSystemSuperuser;
    const canViewOwnBilling = isPatient;
    const canVerifyOrCollectCopay = isFrontDesk;
    return {
      role,
      isAccountOfficer,
      isAdmin,
      isITAdmin,
      isSystemSuperuser,
      isPatient,
      isFrontDesk,
      isClinicalRole,
      canManageFinancialSettlement,
      canViewFinancialOverview,
      canViewOwnBilling,
      canVerifyOrCollectCopay,
      canSeeFinancialNav: isAccountOfficer || isAdmin || isITAdmin || isSystemSuperuser || isPatient || isFrontDesk,
    };
  }, [user?.role]);
}
