import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { FileText, ShieldCheck, HeartPulse, Calendar, Layers } from 'lucide-react';

export default function PatientPortal() {
  const { user } = useAuth();

  const isPatient = user?.role === 'patient';
  const patientId = 'MED-20260505-7890';

  const portalLinks = useMemo(
    () => [
      { title: 'Medical Records', description: 'View diagnostics, prescriptions and care notes.', href: '/records' },
      { title: 'Appointments', description: 'Check your upcoming visits and bookings.', href: '/appointments' },
      { title: 'Billing Summary', description: 'Review invoices and payment status.', href: '/billing' },
    ],
    [],
  );

  if (!user) return null;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Patient Portal</h1>
          <p className="text-muted-foreground">Personal access to your medical records, appointments, and treatment updates.</p>
        </div>
        <div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3">
          <ShieldCheck className="w-5 h-5 text-success" />
          <span className="text-sm text-muted-foreground">Secure health records access is available for registered patients.</span>
        </div>
      </div>

      {!isPatient && (
        <div className="rounded-3xl border border-warning/30 bg-warning/10 p-5 text-warning">
          Patient portal access is reserved for authenticated patients. Please log in as a patient to view your own records.
        </div>
      )}

      {isPatient && (
        <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
          <div className="card-medical p-6 space-y-5">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-sm uppercase tracking-[0.2em] text-muted-foreground">Client ID</p>
                <h2 className="text-xl font-semibold">{patientId}</h2>
              </div>
              <div className="rounded-2xl bg-primary/10 px-3 py-2 text-primary text-sm">Active</div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="rounded-3xl border border-border p-4">
                <p className="text-sm text-muted-foreground">Name</p>
                <p className="font-medium">{user.firstName} {user.lastName}</p>
              </div>
              <div className="rounded-3xl border border-border p-4">
                <p className="text-sm text-muted-foreground">Email</p>
                <p className="font-medium">{user.email}</p>
              </div>
            </div>

            <div className="space-y-4">
              <div className="rounded-3xl border border-border p-4 bg-background/80">
                <div className="flex items-center gap-2 mb-3">
                  <Calendar className="w-4 h-4 text-primary" />
                  <p className="font-semibold">Upcoming Appointment</p>
                </div>
                <p className="text-sm text-muted-foreground">June 10, 2026 — General review with Dr. Sarah Johnson at 10:00 AM.</p>
              </div>
              <div className="rounded-3xl border border-border p-4 bg-background/80">
                <div className="flex items-center gap-2 mb-3">
                  <HeartPulse className="w-4 h-4 text-danger" />
                  <p className="font-semibold">Latest Summary</p>
                </div>
                <p className="text-sm text-muted-foreground">No urgent alerts. Your latest lab review indicates stable glucose and blood pressure control.</p>
              </div>
            </div>
          </div>

          <div className="card-medical p-6 space-y-4">
            <div className="flex items-center gap-3">
              <FileText className="w-5 h-5 text-primary" />
              <p className="text-sm text-muted-foreground">Quick Links</p>
            </div>
            <div className="space-y-3">
              {portalLinks.map((link) => (
                <a key={link.title} href={link.href} className="rounded-3xl border border-border p-4 block hover:bg-muted/50 transition-colors">
                  <p className="font-medium">{link.title}</p>
                  <p className="text-sm text-muted-foreground">{link.description}</p>
                </a>
              ))}
            </div>
            <div className="rounded-3xl border border-border p-4 bg-background/80">
              <p className="font-medium">Patient Record Access</p>
              <p className="text-sm text-muted-foreground">Your medical information is private and available here when you are authenticated as a patient.</p>
            </div>
            <div className="rounded-3xl border border-border p-4 bg-background/80">
              <p className="font-medium">Notes</p>
              <p className="text-sm text-muted-foreground">If you need help, contact your care team through the clinic reception or your assigned physician.</p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
