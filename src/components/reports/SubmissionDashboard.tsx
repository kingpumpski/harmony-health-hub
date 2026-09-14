import { useEffect, useMemo, useState } from 'react';
import { CheckCircle2, Clock3, Loader2, RefreshCw, Send, TriangleAlert } from 'lucide-react';
import { toast } from 'sonner';
import { listSubmissions, markSubmissionsSubmitted, type ReportSubmission } from '@/lib/reportsCenter';

function isOpenSubmission(status: ReportSubmission['status']) {
  return status === 'pending' || status === 'overdue';
}

function statusLabel(status: ReportSubmission['status']) {
  return status === 'accepted' ? 'Accepted' : status === 'rejected' ? 'Rejected' : status === 'submitted' ? 'Submitted' : status === 'overdue' ? 'Overdue' : 'Pending';
}

export default function SubmissionDashboard({ facilityId, period }: { facilityId: string; period: string }) {
  const [rows, setRows] = useState<ReportSubmission[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  async function load(showError = true) {
    setLoading(true);
    try {
      const submissions = await listSubmissions(facilityId, period);
      setRows(submissions);
    } catch (error) {
      if (showError) toast.error(error instanceof Error ? error.message : 'Unable to load submission status.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void load(); }, [facilityId, period]);

  const pending = rows.filter((row) => row.status === 'pending').length;
  const overdue = rows.filter((row) => row.status === 'overdue').length;
  const submitted = rows.filter((row) => ['submitted', 'accepted'].includes(row.status)).length;
  const rejected = rows.filter((row) => row.status === 'rejected').length;
  const completeness = rows.length ? Math.round((submitted / rows.length) * 100) : 0;
  const dueSoon = useMemo(() => rows.filter((row) => isOpenSubmission(row.status)).slice(0, 6), [rows]);

  async function submitAllReady() {
    const ids = rows.filter((row) => isOpenSubmission(row.status)).map((row) => row.id);
    if (!ids.length) return;
    setSaving(true);
    try {
      const updated = await markSubmissionsSubmitted(ids);
      toast.success(updated === ids.length ? `${updated} reporting record${updated === 1 ? '' : 's'} marked as submitted.` : `${updated} of ${ids.length} reporting records were updated.`);
      await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Unable to update submissions.'); }
    finally { setSaving(false); }
  }

  if (loading) return <div className="flex items-center gap-2 py-6 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Loading submission status…</div>;

  return <section className="card-medical p-5 space-y-4">
    <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
      <div><h2 className="text-lg font-semibold">Submission dashboard</h2><p className="text-sm text-muted-foreground">Facility-level completeness and deadline tracking for the selected period.</p></div>
      <div className="flex flex-wrap gap-2">
        <button disabled={saving} className="btn-secondary inline-flex items-center justify-center gap-2 disabled:opacity-50" onClick={() => void load()}><RefreshCw className="h-4 w-4" /> Refresh</button>
        <button disabled={saving || !rows.some((row) => isOpenSubmission(row.status))} className="btn-primary inline-flex items-center justify-center gap-2 disabled:opacity-50" onClick={() => void submitAllReady()}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />} Mark outstanding as submitted</button>
      </div>
    </div>
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
      <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Completeness</p><p className="mt-1 text-2xl font-bold">{completeness}%</p></div>
      <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Submitted</p><p className="mt-1 text-2xl font-bold text-success">{submitted}</p></div>
      <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Pending</p><p className="mt-1 text-2xl font-bold">{pending}</p></div>
      <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Overdue</p><p className="mt-1 text-2xl font-bold text-critical">{overdue}</p></div>
      <div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Rejected</p><p className="mt-1 text-2xl font-bold text-critical">{rejected}</p></div>
    </div>
    {!rows.length ? <p className="rounded-xl border border-dashed p-5 text-sm text-muted-foreground">Generate the selected period first. Submission records are created from the activated monthly report configuration.</p> : <div className="grid gap-2">{dueSoon.map((row) => <div key={row.id} className="flex items-center justify-between gap-3 rounded-xl border p-3"><div className="flex min-w-0 items-center gap-2">{row.status === 'overdue' ? <TriangleAlert className="h-4 w-4 text-critical" /> : row.status === 'submitted' || row.status === 'accepted' ? <CheckCircle2 className="h-4 w-4 text-success" /> : <Clock3 className="h-4 w-4 text-warning" />}<div className="min-w-0"><span className="block truncate text-sm font-medium">{row.report_id}</span><span className="text-xs text-muted-foreground">{statusLabel(row.status)}{row.submission_reference ? ` · Ref ${row.submission_reference}` : ''}</span></div></div><span className="shrink-0 text-xs text-muted-foreground">Due {row.due_date}</span></div>)}</div>}
  </section>;
}
