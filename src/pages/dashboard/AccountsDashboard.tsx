import { Banknote, FilePlus2, ShieldCheck } from 'lucide-react';
import RoleOperationalDashboard from './RoleOperationalDashboard';

export default function AccountsDashboard() {
  return <RoleOperationalDashboard
    role="accountant"
    title="Accounts Dashboard"
    subtitle="Track collections, outstanding invoices and insurance claims requiring follow-up."
    actions={[
      { label: 'Generate Bill', href: '/billing', icon: FilePlus2 },
      { label: 'Process Payment', href: '/billing', icon: Banknote },
      { label: 'View Insurance Claims', href: '/insurance-claims', icon: ShieldCheck },
    ]}
  />;
}
