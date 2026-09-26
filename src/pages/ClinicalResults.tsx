import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { useAuth } from '@/contexts/AuthContext';
import { AlertTriangle, CheckCircle2, Image as ImageIcon, RefreshCw } from 'lucide-react';
import { toast } from '@/hooks/use-toast';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';

interface ResultRow {
  id: string;
  patient_id: string;
  study_name: string;
  modality: string;
  priority: string;
  report: string | null;
  impression: string | null;
  encounter_id: string | null;
  created_at: string;
  updated_at: string;
  patients?: { first_name: string; last_name: string } | null;
}
interface ResultNotification { id: string; related_entity_id: string | null; is_read: boolean }

export default function ClinicalResults() {
  const { user } = useAuth();
  const [results, setResults] = useState<ResultRow[]>([]);
  const [notifications, setNotifications] = useState<ResultNotification[]>([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    if (!user?.id) return;
    setLoading(true);
    const [{ data: imaging }, { data: notes }] = await Promise.all([
      supabase.from('imaging_orders').select('id,patient_id,study_name,modality,priority,report,impression,encounter_id,created_at,updated_at,patients(first_name,last_name)').eq('requested_by', user.id).eq('status', 'completed').order('updated_at', { ascending: false }).limit(100),
      (supabase as any).rpc('get_workflow_notifications', { _limit: 200 }),
    ]);
    setResults((imaging ?? []) as ResultRow[]);
    setNotifications((notes ?? []) as ResultNotification[]);
    setLoading(false);
  }, [user?.id]);

  useEffect(() => {
    void load();
    if (!user?.id) return;
    const channel = supabase.channel(`clinical-results-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'imaging_orders' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, () => void load())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load, user?.id]);

  const unreadResultIds = useMemo(() => new Set(notifications.map((n) => n.related_entity_id).filter(Boolean) as string[]), [notifications]);

  const acknowledge = async (resultId: string) => {
    const matching = notifications.filter((n) => n.related_entity_id === resultId);
    if (!matching.length) return;
    const { error } = await (supabase as any).rpc('mark_notifications_read', { _notification_ids: matching.map((n) => n.id) });
    if (error) {
      playWorkflowSound('critical');
      toast({ title: 'Could not acknowledge result', description: error.message, variant: 'destructive' });
      return;
    }
    playWorkflowSound('success');
    toast({ title: 'Radiology result acknowledged' });
    void load();
  };

  if (!user) return null;
  const pendingCount = results.filter((r) => unreadResultIds.has(r.id)).length;
  const urgentCount = results.filter((r) => ['urgent', 'stat'].includes(r.priority.toLowerCase())).length;

  return (
    <OperationalWorklistShell
      icon={ImageIcon}
      eyebrow="Diagnostics · Results review"
      title="Radiology Results Review"
      description="Review completed diagnostic imaging reports assigned to your clinical workflow and acknowledge each result from one auditable worklist."
      actions={(
        <button type="button" onClick={() => { playWorkflowSound('info'); void load(); }} disabled={loading} className="btn-secondary inline-flex items-center gap-2" aria-label="Refresh radiology results">
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" /> {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      )}
      counters={[
        { label: 'Results to review', value: pendingCount, tone: 'text-warning', surface: 'bg-warning/5' },
        { label: 'Completed results', value: results.length, tone: 'text-success', surface: 'bg-success/5' },
        { label: 'Urgent / STAT', value: urgentCount, tone: 'text-critical', surface: 'bg-critical/5' },
      ]}
      beforeList={pendingCount > 0 ? (
        <div className="rounded-xl border border-warning/30 bg-warning/5 p-3 flex items-center gap-2 text-sm" role="status" aria-live="polite">
          <AlertTriangle className="w-4 h-4 text-warning shrink-0" aria-hidden="true" />
          <span>{pendingCount} diagnostic result{pendingCount === 1 ? '' : 's'} require{pendingCount === 1 ? 's' : ''} clinical acknowledgement.</span>
        </div>
      ) : undefined}
      listTitle="Radiology results worklist"
      listDescription="Completed reports remain visible with their clinical impression and acknowledgement state."
      listMeta={`${results.length} result${results.length === 1 ? '' : 's'}`}
      loading={loading}
      empty={results.length === 0}
      emptyTitle="No completed radiology results"
      emptyDescription="Completed diagnostic imaging assigned to your workflow will appear here."
    >
      {results.map((result) => {
        const unread = unreadResultIds.has(result.id);
        const urgent = ['urgent', 'stat'].includes(result.priority.toLowerCase());
        return (
          <article key={result.id} className={`p-5 space-y-4 ${unread ? 'bg-primary/5' : ''}`}>
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="font-semibold">{result.study_name} · {result.modality}</h2>
                  {unread && <span className="rounded-full bg-warning/10 px-2.5 py-1 text-[10px] font-semibold text-warning">Needs acknowledgement</span>}
                  {urgent && <span className="rounded-full bg-critical/10 px-2.5 py-1 text-[10px] font-semibold text-critical">Urgent / STAT</span>}
                </div>
                <p className="mt-1 text-sm text-muted-foreground">{result.patients?.first_name} {result.patients?.last_name} · {result.priority} · Completed {new Date(result.updated_at).toLocaleString()}</p>
              </div>
              {unread ? (
                <button type="button" onClick={() => void acknowledge(result.id)} className="btn-primary inline-flex items-center gap-2 text-xs shrink-0">
                  <CheckCircle2 className="w-4 h-4" aria-hidden="true" /> Acknowledge result
                </button>
              ) : <span className="badge-success shrink-0">Acknowledged</span>}
            </div>
            <div className="grid gap-3 md:grid-cols-2">
              <section className="rounded-xl border border-border p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Radiology report</p>
                <p className="mt-2 whitespace-pre-wrap text-sm">{result.report || 'No narrative report entered.'}</p>
              </section>
              <section className="rounded-xl border border-primary/20 bg-primary/5 p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Impression</p>
                <p className="mt-2 whitespace-pre-wrap text-sm font-medium">{result.impression || 'No impression entered.'}</p>
              </section>
            </div>
          </article>
        );
      })}
    </OperationalWorklistShell>
  );
}
