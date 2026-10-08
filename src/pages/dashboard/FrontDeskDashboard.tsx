import { Calendar, CreditCard, FileText, ListChecks, UserPlus, Users } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

const actions = [
  { label: 'Register patient', description: 'Create or update a patient registration.', href: '/registration', icon: UserPlus },
  { label: 'Appointment worklist', description: 'Open the complete appointment queue and actions.', href: '/appointments', icon: Calendar },
  { label: 'Patient directory', description: 'Find patients using the authorized directory.', href: '/patients', icon: Users },
  { label: 'Department queue', description: 'Review active service handoffs and queues.', href: '/department-queue', icon: ListChecks },
  { label: 'Payment handoff', description: 'Open billing and payment workflows.', href: '/billing', icon: CreditCard },
] as const;

export default function FrontDeskDashboard() {
  const navigate = useNavigate();
  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Users className="w-6 h-6 text-primary" />Front Desk Operations</h1>
        <p className="mt-1 text-muted-foreground">Focused entry points for registration, appointments, queues, patient lookup and payment handoff.</p>
      </div>
      <section aria-label="Front desk workspaces" className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {actions.map(({ label, description, href, icon: Icon }) => (
          <button key={href} type="button" onClick={() => navigate(href)} className="card-medical group p-5 text-left transition-all hover:-translate-y-0.5 hover:shadow-elevated focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            <div className="flex items-start gap-3"><div className="rounded-xl bg-primary/10 p-2.5 text-primary"><Icon className="h-5 w-5" /></div><div className="min-w-0"><h2 className="font-semibold">{label}</h2><p className="mt-1 text-xs leading-5 text-muted-foreground">{description}</p><span className="mt-3 inline-flex items-center gap-1 text-xs font-medium text-primary"><FileText className="h-3.5 w-3.5" />Open workspace</span></div></div>
          </button>
        ))}
      </section>
    </div>
  );
}
