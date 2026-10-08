import { Calendar, CreditCard, UserPlus, Users, ListChecks } from 'lucide-react';
import { Link } from 'react-router-dom';

const actions = [
  { href: '/registration', label: 'Register patient', description: 'Create or update a patient registration.', icon: UserPlus, primary: true },
  { href: '/appointments', label: 'Appointment worklist', description: 'Book, check in and manage today’s visits.', icon: Calendar },
  { href: '/patients', label: 'Patient directory', description: 'Find existing patients and open their records.', icon: Users },
  { href: '/department-queue', label: 'Department queue', description: 'Monitor waiting patients and handoffs.', icon: ListChecks },
  { href: '/billing', label: 'Payment handoff', description: 'Open outstanding billing items when payment handling is required.', icon: CreditCard },
];

export default function FrontDeskDashboard() {
  return (
    <div className="space-y-6 animate-fade-in">
      <header className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-primary">Patient Access</p>
          <h1 className="mt-1 flex items-center gap-2 text-2xl font-heading font-bold">
            <Users className="h-6 w-6 text-primary" />
            Front Desk Operations
          </h1>
          <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
            Registration, appointments, patient lookup and operational handoffs. Detailed worklists remain in their dedicated workspaces.
          </p>
        </div>
      </header>

      <section aria-labelledby="front-desk-actions">
        <div className="mb-3">
          <h2 id="front-desk-actions" className="font-semibold">Today’s work</h2>
          <p className="text-xs text-muted-foreground">Open only the workflow you need.</p>
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {actions.map(({ href, label, description, icon: Icon, primary }) => (
            <Link
              key={href}
              to={href}
              className={`card-medical p-5 transition-colors hover:border-primary/40 ${primary ? 'border-primary/30 bg-primary/5' : ''}`}
            >
              <Icon className="h-5 w-5 text-primary" />
              <h3 className="mt-3 font-semibold">{label}</h3>
              <p className="mt-1 text-sm text-muted-foreground">{description}</p>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
