import { ClipboardCheck, FileText, Settings2 } from 'lucide-react';
import RoleOperationalDashboard from './RoleOperationalDashboard';

export default function LabTechDashboard() {
  return <RoleOperationalDashboard
    role="lab_technician"
    title="Laboratory Dashboard"
    subtitle="Monitor incoming samples, tests in progress and results awaiting review."
    actions={[
      { label: 'Enter Results', href: '/laboratory?status=in_progress', icon: ClipboardCheck },
      { label: 'Print Report', href: '/lab-results', icon: FileText },
      { label: 'Manage Test Catalogue', href: '/laboratory?tab=catalogue', icon: Settings2 },
    ]}
  />;
}
