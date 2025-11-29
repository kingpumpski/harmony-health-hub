import { useAuth } from '@/contexts/AuthContext';
import FrontDeskDashboard from './dashboard/FrontDeskDashboard';
import PractitionerDashboard from './dashboard/PractitionerDashboard';
import NurseDashboard from './dashboard/NurseDashboard';
import LabTechDashboard from './dashboard/LabTechDashboard';
import PharmacyDashboard from './dashboard/PharmacyDashboard';
import AccountsDashboard from './dashboard/AccountsDashboard';
import AdminDashboard from './dashboard/AdminDashboard';
import CanteenDashboard from './dashboard/CanteenDashboard';

export default function Dashboard() {
  const { user } = useAuth();

  if (!user) return null;

  switch (user.role) {
    case 'admin':
      return <AdminDashboard />;
    case 'practitioner':
      return <PractitionerDashboard />;
    case 'nurse':
    case 'midwife':
      return <NurseDashboard />;
    case 'lab_technician':
      return <LabTechDashboard />;
    case 'pharmacist':
      return <PharmacyDashboard />;
    case 'accountant':
      return <AccountsDashboard />;
    case 'canteen':
      return <CanteenDashboard />;
    case 'front_desk':
    default:
      return <FrontDeskDashboard />;
  }
}
