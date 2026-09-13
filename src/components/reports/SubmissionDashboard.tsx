import { useEffect, useMemo, useState } from 'react';
import { CheckCircle2, Clock3, Loader2, Send, TriangleAlert } from 'lucide-react';
import { toast } from 'sonner';
import { listSubmissions, markSubmissionsSubmitted, type ReportSubmission } from '@/lib/reportsCenter';

export default function SubmissionDashboard({ facilityId, period }: { facilityId: string; period: string }) {
  const [rows, setRows] = useState<ReportSubmission[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  async function load() {
    setLoading(true);
    try {
      const submissions = await listSubmissions(facilityId, period);
      const today = new Date().toISOString().slice(0, 10);
      setRows(submissions.map((row) => row.status === 'pending' && row.due_date < today ? { ...row, status: 'overdue' } : row));
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Unable to load submission status.'); }
    finally { setLoading(false); }
  }

  useEffect(() => { void load(); }, [facilityId, period]);

  const pending = rows.filter((row) => row.status === 'pending').length;
  const overdue = rows.filter((row) => row.status === 'overdue').length;
  const submitted = rows.filter((row) => ['submitted', 'accepted'].includes(row.status)).length;
  const completeness = rows.length ? Math.round((submitted / rows.length) * 100) : 0;
  const dueSoon = useMemo(() => rows.filter((row) => row.status === 'pending').slice(0, 6), [rows]);

  async function submitAllReady() {
    const ids = rows.filter((row) => ['pending', 'overdue'].includes(row.status)).map((row) => row.id);
    if (!ids.length) return;
    setSaving(true);
    try { await markSubmissionsSubmitted(ids); toast.success('Selected reporting records marked as submitted.'); await load(); }
    catch (error) { toast.error(error instanceof Error ? error.message : 'Unable to update submissions.'); }
    finally { setSaving(false); }
  }

  if (loading) return <div className="flex items-center gap-2 py-6 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Loading submission status…</div>;

  return <section className="card-medical p-5 space-y-4">
    <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
      <div><h2 className="text-lg font-semibold">Submission dashboard</h2><p className="text-sm text-muted-foreground">Facility-level completeness and deadline tracking for the selected period.</p></div>
      <button disabled={saving || !rows.some((row) => ['pending', 'overdue'].includes(row.status))} className="btn-primary inline-flex items-center justify-center gap-2 disabled:opacity-50" onClick={() => void submitAllReady()}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />} Mark outstanding as submitted</button>
    </div>
    <div className="grid gap-3 sm:grid-cols-4">
      <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Completeness</p><p className="mt-1 text-2xl font-bold">{completeness}%</p></div>
      <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Submitted</p><p className="mt-1 text-2xl font-bold text-success">{submitted}</p></div>
      <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Pending</p><p className="mt-1 text-2xl font-bold">{pending}</p></div>
      <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Overdue</p><p className="mt-1 text-2xl font-bold text-critical">{overdue}</p></div>
    </div>
    {!rows.length ? <p className="rounded-xl border border-dashed p-5 text-sm text-muted-foreground">Generate the selected period first. Submission records are created from the activated monthly report configuration.</p> : <div className="grid gap-2">{dueSoon.map((row) => <div key={row.id} className="flex items-center justify-between gap-3 rounded-xl border p-3"><div className="flex min-w-0 items-center gap-2">{row.status === 'overdue' ? <TriangleAlert className="h-4 w-4 text-critical" /> : row.status === 'submitted' ? <CheckCircle2 className="h-4 w-4 text-success" /> : <Clock3 className="h-4 w-4 text-warning" />}<span className="truncate text-sm font-medium">{row.report_id}</span></div><span className="text-xs text-muted-foreground">Due {row.due_date}</span></div>)}</div>}
  </section>;
}
