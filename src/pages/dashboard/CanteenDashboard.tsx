import { Link } from 'react-router-dom';
import { AlertTriangle, BedDouble, ClipboardList, Utensils } from 'lucide-react';

/**
 * Catering role compatibility surface.
 *
 * The repository does not currently expose a server-backed canteen/menu/order
 * domain. Do not present fabricated patients, meals, staff orders or counts.
 * This surface therefore provides safe operational entry points until that
 * domain is introduced with authoritative tables and workflow RPCs.
 */
export default function CanteenDashboard() {
  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-primary">Support Services</p>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Utensils className="w-6 h-6 text-primary" /> Dietary & Kitchen Operations</h1>
        <p className="text-muted-foreground mt-1">Catering workspace entry points without synthetic patient or order data.</p>
      </div>

      <section className="rounded-xl border border-warning/30 bg-warning/5 p-5 flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 text-warning mt-0.5 shrink-0" />
        <div>
          <h2 className="font-semibold">Catering data workflow not yet connected</h2>
          <p className="text-sm text-muted-foreground mt-1">
            The current database and application architecture do not expose authoritative meal plans, dietary orders or kitchen-status records. The dashboard will not invent those records. Connect the catering domain before enabling transactional kitchen actions.
          </p>
        </div>
      </section>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Link to="/admissions" className="card-medical p-5 hover:border-primary/40 transition-colors">
          <BedDouble className="w-5 h-5 text-primary mb-3" />
          <p className="font-semibold">Inpatient census</p>
          <p className="text-sm text-muted-foreground mt-1">Review current admissions from the authoritative inpatient workflow.</p>
        </Link>
        <Link to="/reports" className="card-medical p-5 hover:border-primary/40 transition-colors">
          <ClipboardList className="w-5 h-5 text-info mb-3" />
          <p className="font-semibold">Operational reports</p>
          <p className="text-sm text-muted-foreground mt-1">Use the reporting center for currently supported facility data.</p>
        </Link>
        <Link to="/admin/settings" className="card-medical p-5 hover:border-primary/40 transition-colors">
          <Utensils className="w-5 h-5 text-warning mb-3" />
          <p className="font-semibold">Facility configuration</p>
          <p className="text-sm text-muted-foreground mt-1">Review facility workflow configuration before introducing a catering module.</p>
        </Link>
      </div>
    </div>
  );
}
