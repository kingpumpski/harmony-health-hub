import { Fragment, useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { useAuth } from '@/contexts/AuthContext';
import { AlertTriangle, CheckCircle2, Image as ImageIcon, RefreshCw } from 'lucide-react';
import { toast } from '@/hooks/use-toast';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import ClinicalDataTable, { ClinicalProgressBar, ClinicalStatusBadge, ClinicalTableAction } from '@/components/workflow/ClinicalDataTable';

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
  const [reviewFilter, setReviewFilter] = useState('all');
  const [priorityFilter, setPriorityFilter] = useState('all');
  const [modalityFilter, setModalityFilter] = useState('all');
  const [appliedFilters, setAppliedFilters] = useState({ review: 'all', priority: 'all', modality: 'all' });
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user?.id) return;
    setLoading(true);
    const [{ data: imaging, error: imagingError }, { data: notes }] = await Promise.all([
      supabase.from('imaging_orders').select('id,patient_id,study_name,modality,priority,report,impression,encounter_id,created_at,updated_at,patients(first_name,last_name)').eq('requested_by', user.id).eq('status', 'completed').order('updated_at', { ascending: false }).limit(100),
      (supabase as any).rpc('get_workflow_notifications', { _limit: 200 }),
    ]);
    if (imagingError) {
      toast({ title: 'Radiology results unavailable', description: imagingError.message, variant: 'destructive' });
      setResults([]);
    } else {
      setResults((imaging ?? []) as ResultRow[]);
    }
    setNotifications((notes ?? []) as ResultNotification[]);
    setLoading(false);
  }, [user?.id]);

  useEffect(() => {
    void load();
    if (!user?.id) return;
    const channel = supabase.channel(`clinical-results-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'imaging_orders' }, () => void load())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load, user?.id]);

  const unreadResultIds = useMemo(() => new Set(notifications.filter((n) => !n.is_read).map((n) => n.related_entity_id).filter(Boolean) as string[]), [notifications]);

  const acknowledge = async (resultId: string) => {
    const matching = notifications.filter((n) => n.related_entity_id === resultId && !n.is_read);
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

  const modalities = useMemo(() => Array.from(new Set(results.map((r) => r.modality).filter(Boolean))).sort(), [results]);
  const visibleResults = useMemo(() => results.filter((result) => {
    const reviewMatches = appliedFilters.review === 'all'
      || (appliedFilters.review === 'pending' && unreadResultIds.has(result.id))
      || (appliedFilters.review === 'acknowledged' && !unreadResultIds.has(result.id));
    const priorityMatches = appliedFilters.priority === 'all' || result.priority.toLowerCase() === appliedFilters.priority;
    const modalityMatches = appliedFilters.modality === 'all' || result.modality === appliedFilters.modality;
    return reviewMatches && priorityMatches && modalityMatches;
  }), [results, appliedFilters, unreadResultIds]);

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
      listDescription="Completed reports remain visible with clinical status, workflow progress and auditable actions."
      listMeta={`${visibleResults.length} shown · ${results.length} total`}
      loading={false}
      empty={false}
      listContent={(
        <ClinicalDataTable
          title="Diagnostic imaging results"
          description="Use clinical filters to narrow the review queue. Patient and study information remains specific to the medical workflow."
          meta={`${visibleResults.length} result${visibleResults.length === 1 ? '' : 's'}`}
          filters={[
            { label: 'Review state', value: reviewFilter, onChange: setReviewFilter, options: [{ value: 'all', label: 'All review states' }, { value: 'pending', label: 'Needs acknowledgement' }, { value: 'acknowledged', label: 'Acknowledged' }] },
            { label: 'Priority', value: priorityFilter, onChange: setPriorityFilter, options: [{ value: 'all', label: 'All priorities' }, { value: 'routine', label: 'Routine' }, { value: 'urgent', label: 'Urgent' }, { value: 'stat', label: 'STAT' }] },
            { label: 'Modality', value: modalityFilter, onChange: setModalityFilter, options: [{ value: 'all', label: 'All modalities' }, ...modalities.map((value) => ({ value, label: value }))] },
          ]}
          onSearch={() => setAppliedFilters({ review: reviewFilter, priority: priorityFilter, modality: modalityFilter })}
          loading={loading}
          empty={visibleResults.length === 0}
          emptyMessage="No completed radiology results match the selected clinical filters."
        >
          <thead>
            <tr>
              <th scope="col">Patient</th>
              <th scope="col">Study</th>
              <th scope="col">Priority</th>
              <th scope="col">Status</th>
              <th scope="col">Workflow progress</th>
              <th scope="col">Report date</th>
              <th scope="col" className="text-right">Action</th>
            </tr>
          </thead>
          <tbody>
            {visibleResults.map((result) => {
              const unread = unreadResultIds.has(result.id);
              const urgent = ['urgent', 'stat'].includes(result.priority.toLowerCase());
              return (
                <Fragment key={result.id}>
                  <tr className={unread ? 'bg-warning/5' : undefined}>
                    <td>
                      <div className="min-w-[170px]">
                        <p className="font-semibold">{result.patients?.first_name} {result.patients?.last_name}</p>
                        <p className="mt-0.5 text-xs text-muted-foreground">Patient record · {result.patient_id.slice(0, 8)}</p>
                      </div>
                    </td>
                    <td>
                      <div className="min-w-[190px]">
                        <p className="font-medium">{result.study_name}</p>
                        <p className="mt-0.5 text-xs text-muted-foreground">{result.modality}</p>
                      </div>
                    </td>
                    <td>{urgent ? <ClinicalStatusBadge status={result.priority} /> : <ClinicalStatusBadge status="started" label="Routine" />}</td>
                    <td><ClinicalStatusBadge status={unread ? 'pending' : 'acknowledged'} /></td>
                    <td><ClinicalProgressBar value={100} label="Completed" /></td>
                    <td className="whitespace-nowrap text-xs text-muted-foreground">{new Date(result.updated_at).toLocaleString()}</td>
                    <td>
                      <div className="flex min-w-[190px] justify-end gap-2">
                        <ClinicalTableAction label={expandedId === result.id ? 'Hide report' : 'View report'} onClick={() => setExpandedId(expandedId === result.id ? null : result.id)} />
                        {unread && <ClinicalTableAction label="Acknowledge" icon="acknowledge" onClick={() => void acknowledge(result.id)} />}
                      </div>
                    </td>
                  </tr>
                  {expandedId === result.id && (
                    <tr key={`${result.id}-details`} className="bg-muted/20">
                      <td colSpan={7}>
                        <div className="grid gap-3 md:grid-cols-2">
                          <section className="rounded-xl border border-border bg-background p-4">
                            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Radiology report</p>
                            <p className="mt-2 whitespace-pre-wrap text-sm">{result.report || 'No narrative report entered.'}</p>
                          </section>
                          <section className="rounded-xl border border-primary/20 bg-primary/5 p-4">
                            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Impression</p>
                            <p className="mt-2 whitespace-pre-wrap text-sm font-medium">{result.impression || 'No impression entered.'}</p>
                          </section>
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              );
            })}
          </tbody>
        </ClinicalDataTable>
      )}
      >
      </OperationalWorklistShell>
  );
}
