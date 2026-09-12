import { useAuth } from '@/contexts/AuthContext';
import WorkflowSummary from '@/components/WorkflowSummary';
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
  let dashboard;
  switch (String(user.role)) {
    case 'admin': dashboard = <AdminDashboard />; break;
    case 'practitioner': dashboard = <PractitionerDashboard />; break;
    case 'nurse':
    case 'midwife':
    case 'specialist_nurse': dashboard = <NurseDashboard />; break;
    case 'lab_technician': dashboard = <LabTechDashboard />; break;
    case 'pharmacist': dashboard = <PharmacyDashboard />; break;
    case 'accountant': dashboard = <AccountsDashboard />; break;
    case 'canteen': dashboard = <CanteenDashboard />; break;
    case 'front_desk':
    default: dashboard = <FrontDeskDashboard />; break;
  }
  return <><WorkflowSummary />{dashboard}</>;
}
