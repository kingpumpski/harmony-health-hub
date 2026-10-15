import { useAuth } from '@/contexts/AuthContext';
import AdminFinancialOverview from '@/pages/AdminFinancialOverview';
import Billing from '@/pages/Billing';

export default function FinancialReportsRoute() {
  const { user } = useAuth();
  if (user?.role === 'admin' || user?.role === 'it_admin' || user?.role === 'system_superuser') {
    return <AdminFinancialOverview />;
  }
  return <Billing />;
}
