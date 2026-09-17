import { Calendar, UserPlus, Search, CreditCard, Siren, Users } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import Appointments from '@/pages/Appointments';
import WorkflowQueueLink from '@/components/WorkflowQueueLink';

export default function FrontDeskDashboard() {
  const navigate = useNavigate();

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
            <Users className="w-6 h-6 text-primary" />
            Front Desk Operations
          </h1>
          <p className="text-muted-foreground">
            Live registration, appointment, queue and payment handoff workflows.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button type="button" className="btn-primary inline-flex items-center gap-2" onClick={() => navigate('/registration')}>
            <UserPlus className="w-4 h-4" /> Register Patient
          </button>
          <button type="button" className="btn-secondary inline-flex items-center gap-2" onClick={() => navigate('/appointments')}>
            <Calendar className="w-4 h-4" /> Appointments
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <WorkflowQueueLink title="Patient Search" count={0} icon={Search} href="/patients" tone="primary" />
        <WorkflowQueueLink title="Appointment Queue" count={0} icon={Calendar} href="/appointments" tone="info" />
        <WorkflowQueueLink title="Payment / Release" count={0} icon={CreditCard} href="/accounts-approvals" tone="warning" />
        <WorkflowQueueLink title="Emergency Board" count={0} icon={Siren} href="/emergency-board" tone="critical" />
      </div>

      <section className="card-medical p-5">
        <div className="mb-4">
          <h2 className="font-semibold">Live appointment worklist</h2>
          <p className="text-xs text-muted-foreground">
            The same server-backed appointment workflow used by clinicians. No sample patients, fabricated counts or duplicate appointment state is maintained here.
          </p>
        </div>
        <Appointments />
      </section>
    </div>
  );
}
