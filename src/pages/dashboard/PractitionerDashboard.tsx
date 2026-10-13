import { ClipboardPlus, FilePlus2, FlaskConical, Stethoscope } from 'lucide-react';
import RoleOperationalDashboard from './RoleOperationalDashboard';

export default function PractitionerDashboard() {
  return <RoleOperationalDashboard
    role="practitioner"
    title="Clinician Dashboard"
    subtitle="Your appointments, diagnostic results and inpatient work in one clinical overview."
    actions={[
      { label: 'Start Encounter', href: '/encounters', icon: Stethoscope },
      { label: 'Order Lab', href: '/encounters', icon: FlaskConical },
      { label: 'Order Radiology', href: '/encounters', icon: FilePlus2 },
      { label: 'Write Prescription', href: '/encounters', icon: ClipboardPlus },
    ]}
  />;
}
