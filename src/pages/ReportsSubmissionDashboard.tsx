import { useEffect, useState } from 'react';
import { Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import SubmissionDashboard from '@/components/reports/SubmissionDashboard';
import { listFacilities, type HealthcareFacility } from '@/lib/reportsCenter';

function previousMonth() {
  const date = new Date();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() - 1);
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
}

export default function ReportsSubmissionDashboard() {
  const [facilities, setFacilities] = useState<HealthcareFacility[]>([]);
  const [facilityId, setFacilityId] = useState('');
  const [period, setPeriod] = useState(previousMonth());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    listFacilities().then((rows) => {
      setFacilities(rows);
      setFacilityId(rows[0]?.id ?? '');
    }).catch((error) => toast.error(error instanceof Error ? error.message : 'Unable to load facilities.')).finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="flex min-h-[50vh] items-center justify-center"><Loader2 className="h-6 w-6 animate-spin text-primary" /></div>;

  return <div className="space-y-6 animate-fade-in">
    <div>
      <p className="text-sm font-medium text-primary">Ministry Reporting & Compliance</p>
      <h1 className="mt-1 text-2xl font-heading font-bold">Submission Dashboard</h1>
      <p className="text-muted-foreground">Track reporting completeness, pending returns and overdue submissions for the selected facility and period.</p>
    </div>
    <div className="card-medical p-5 grid gap-3 sm:grid-cols-2">
      <label className="text-sm font-medium">Facility<select className="input mt-2 w-full" value={facilityId} onChange={(event) => setFacilityId(event.target.value)}>{facilities.map((facility) => <option key={facility.id} value={facility.id}>{facility.name}</option>)}</select></label>
      <label className="text-sm font-medium">Reporting period<input className="input mt-2 w-full" type="month" value={period} onChange={(event) => setPeriod(event.target.value)} /></label>
    </div>
    {facilityId ? <SubmissionDashboard facilityId={facilityId} period={period} /> : <div className="card-medical p-6 text-sm text-muted-foreground">No facility is configured for reporting yet.</div>}
  </div>;
}
