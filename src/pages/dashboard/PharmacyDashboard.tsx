import { Boxes, PackageSearch, Pill } from 'lucide-react';
import RoleOperationalDashboard from './RoleOperationalDashboard';

export default function PharmacyDashboard() {
  return <RoleOperationalDashboard
    role="pharmacist"
    title="Pharmacy Dashboard"
    subtitle="Review prescriptions ready to dispense and keep an eye on inventory."
    actions={[
      { label: 'Dispense Medication', href: '/pharmacy', icon: Pill },
      { label: 'Inventory Management', href: '/inventory', icon: Boxes },
      { label: 'View Stock Levels', href: '/inventory', icon: PackageSearch },
    ]}
  />;
}
