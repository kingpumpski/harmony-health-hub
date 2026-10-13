import { Activity, CalendarDays, ScanLine, Stethoscope } from 'lucide-react';
import { Link } from 'react-router-dom';
import DashboardLayout from '@/components/layouts/DashboardLayout';

export default function OrthopaedicDashboard() {
  return (
    <DashboardLayout
      headerTitle="Orthopaedic Dashboard"
      headerSubtitle="A focused workspace for musculoskeletal assessments, imaging and surgical follow-up."
      kpiCards={[
        { label: 'Fracture Clinics', value: '—', description: 'Clinic data is not available in the current workflow feed', href: '/appointments', icon: CalendarDays },
        { label: 'Imaging Reviews', value: '—', description: 'Review imaging work in the clinical results queue', href: '/clinical-results', icon: ScanLine },
        { label: 'Post-Op Reviews', value: '—', description: 'Post-operative review records are not configured', href: '/appointments', icon: Activity },
      ]}
      mainContent={
        <section className="rounded-xl border border-border bg-white p-5 shadow-sm">
          <h2 className="font-semibold">Orthopaedic worklist</h2>
          <p className="mt-1 text-sm text-muted-foreground">Start an encounter to document assessment findings, or review imaging and surgical schedules.</p>
          <div className="mt-4 flex flex-wrap gap-2">
            <Link to="/encounters?specialty=orthopaedic" className="btn-primary inline-flex items-center gap-2"><Stethoscope className="h-4 w-4" /> New assessment</Link>
            <Link to="/clinical-results" className="btn-secondary inline-flex items-center gap-2"><ScanLine className="h-4 w-4" /> Imaging reviews</Link>
            <Link to="/theatre-board" className="btn-secondary inline-flex items-center gap-2"><Activity className="h-4 w-4" /> Surgical planning</Link>
          </div>
        </section>
      }
      sideContent={
        <section className="rounded-xl border border-border bg-white p-5 shadow-sm">
          <h2 className="font-semibold">Quick actions</h2>
          <div className="mt-3 grid gap-2">
            <Link to="/encounters?specialty=orthopaedic" className="btn-secondary">New musculoskeletal assessment</Link>
            <Link to="/appointments" className="btn-secondary">Fracture clinic schedule</Link>
            <Link to="/theatre-board" className="btn-secondary">Surgical planning</Link>
          </div>
        </section>
      }
    />
  );
}
