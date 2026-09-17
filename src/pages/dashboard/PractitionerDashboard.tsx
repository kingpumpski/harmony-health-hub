import Appointments from '@/pages/Appointments';
import ClinicalResults from '@/pages/ClinicalResults';
import { Calendar, Stethoscope, ClipboardList, Baby, Brain } from 'lucide-react';
import { Link } from 'react-router-dom';

/**
 * Practitioner role dashboard compatibility surface.
 *
 * Appointment, result and queue state is owned by the live clinical modules
 * and the shared WorkflowSummary rendered by Dashboard. This role surface
 * intentionally composes those workflows rather than maintaining a second set
 * of fabricated counters or clinical records.
 */
export default function PractitionerDashboard() {
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-primary">Clinical Workspace</p>
          <h1 className="text-2xl font-heading font-bold">Clinical Operations</h1>
          <p className="text-muted-foreground">Live appointments, result review and downstream clinical workflows.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link to="/appointments" className="btn-secondary inline-flex items-center gap-2"><Calendar className="w-4 h-4" /> My Schedule</Link>
          <Link to="/encounters" className="btn-primary inline-flex items-center gap-2"><Stethoscope className="w-4 h-4" /> Encounters</Link>
        </div>
      </div>

      <section className="card-medical p-5">
        <div className="mb-4">
          <h2 className="font-semibold">Live appointment worklist</h2>
          <p className="text-xs text-muted-foreground">Server-backed patient queue and encounter handoff. Shared workflow counters remain the single source of truth.</p>
        </div>
        <Appointments />
      </section>

      <section className="card-medical p-5">
        <div className="mb-4">
          <h2 className="font-semibold">Clinical results review</h2>
          <p className="text-xs text-muted-foreground">Completed diagnostic results assigned to the logged-in clinician.</p>
        </div>
        <ClinicalResults />
      </section>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Link to="/department-queue" className="card-medical p-4 hover:border-primary/40 transition-colors"><ClipboardList className="w-5 h-5 text-primary mb-2" /><p className="font-semibold">Department Queue</p><p className="text-sm text-muted-foreground mt-1">Coordinate service flow and patient movement.</p></Link>
        <Link to="/ai-clinical" className="card-medical p-4 hover:border-primary/40 transition-colors"><Brain className="w-5 h-5 text-primary mb-2" /><p className="font-semibold">AI Clinical Hub</p><p className="text-sm text-muted-foreground mt-1">Open assisted review with clinician oversight.</p></Link>
        <Link to="/fertility" className="card-medical p-4 hover:border-primary/40 transition-colors"><Baby className="w-5 h-5 text-primary mb-2" /><p className="font-semibold">Fertility Services</p><p className="text-sm text-muted-foreground mt-1">Move directly into fertility-specific workflows.</p></Link>
      </div>
    </div>
  );
}
