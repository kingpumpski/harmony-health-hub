import { Bell, CheckCircle, AlertTriangle, MessageSquare } from 'lucide-react';

const notifications = [
  { id: 'N-001', title: 'Critical Patient Alert', message: 'Patient client ID MED-2026-0001 needs rapid response.', priority: 'critical' },
  { id: 'N-002', title: 'Lab Result Ready', message: 'Blood chemistry result uploaded for review.', priority: 'high' },
  { id: 'N-003', title: 'New Admission', message: 'Ward bed assigned for client MED-2026-0004.', priority: 'medium' },
];

export default function Notifications() {
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Notifications</h1>
          <p className="text-muted-foreground">Real-time clinical alerts, lab notices, and patient updates.</p>
        </div>
        <div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3">
          <Bell className="w-5 h-5 text-warning" />
          <span className="text-sm text-muted-foreground">Only authorized staff receive priority alerts.</span>
        </div>
      </div>

      <div className="grid gap-4">
        {notifications.map((item) => (
          <div key={item.id} className="card-medical p-5 rounded-3xl border border-border hover:shadow-md transition-shadow">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-lg font-semibold">{item.title}</p>
                <p className="mt-1 text-sm text-muted-foreground">{item.message}</p>
              </div>
              <span className={`rounded-full px-3 py-1 text-xs font-semibold ${item.priority === 'critical' ? 'bg-critical/10 text-critical' : item.priority === 'high' ? 'bg-warning/10 text-warning' : 'bg-success/10 text-success'}`}>
                {item.priority.toUpperCase()}
              </span>
            </div>
            <div className="mt-4 flex items-center gap-3 text-sm text-muted-foreground">
              <MessageSquare className="w-4 h-4" />
              <span>Actions are available in the lab and clinician dashboards.</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
