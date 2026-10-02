import { Activity, HeartPulse, Stethoscope } from 'lucide-react';
import { useLocation } from 'react-router-dom';

const routeModules: Array<[string, string]> = [
  ['/clinical-operations', 'Healthcare'],
  ['/encounters', 'Healthcare'],
  ['/consultation', 'Healthcare'],
  ['/vitals', 'Triage & Vitals'],
  ['/appointments', 'Appointments'],
  ['/patients', 'Patients'],
  ['/billing', 'Billing'],
  ['/finance', 'Billing'],
  ['/invoices', 'Billing'],
  ['/insurance-claims', 'NHIS Claims'],
  ['/insurance', 'NHIS Claims'],
  ['/laboratory', 'Laboratory'],
  ['/lab-results', 'Laboratory Results'],
  ['/radiology', 'Radiology'],
  ['/imaging', 'Radiology'],
  ['/pharmacy', 'Pharmacy'],
  ['/inpatient', 'Inpatient Care'],
  ['/admissions', 'Admissions'],
  ['/notifications', 'Notifications'],
  ['/admin/settings', 'System Settings'],
  ['/admin', 'Administration'],
  ['/it-support', 'IT Support'],
  ['/reports', 'Reports'],
];

export function routeModuleLabel(pathname: string): string {
  const match = routeModules.find(([prefix]) => pathname === prefix || pathname.startsWith(`${prefix}/`));
  if (match) return match[1];
  const segment = pathname.split('/').filter(Boolean).filter((value) => !/^[0-9a-f-]{8,}$/i.test(value)).pop();
  return segment ? segment.replace(/-/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase()) : 'Dashboard';
}

export default function RouteLoadingScreen() {
  const { pathname } = useLocation();
  const moduleName = routeModuleLabel(pathname);
  const Icon = moduleName === 'Healthcare' ? Stethoscope : moduleName === 'Dashboard' ? HeartPulse : Activity;

  return (
    <div className="flex min-h-[40vh] items-center justify-center p-8" role="status" aria-live="polite" aria-busy="true">
      <div className="flex flex-col items-center gap-4 text-center">
        <div className="relative flex h-16 w-16 items-center justify-center rounded-2xl border border-primary/20 bg-primary/5 text-primary">
          <span className="absolute inset-0 rounded-2xl bg-primary/10 motion-safe:animate-ping motion-reduce:animate-none" aria-hidden="true" />
          <Icon className="relative h-8 w-8 motion-safe:animate-pulse motion-reduce:animate-none" aria-hidden="true" />
        </div>
        <div>
          <p className="font-semibold text-foreground">Loading {moduleName}…</p>
          <p className="mt-1 text-xs text-muted-foreground">Preparing your workspace securely.</p>
        </div>
      </div>
    </div>
  );
}
