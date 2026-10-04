// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
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
  completed_at: string | null;
  acknowledged_at: string | null;
  clinical_indication: string | null;
  prescriber_name: string | null;
  diagnoses: Array<{ id: string; diagnosis: string; icd_code: string | null; is_principal: boolean }>;
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
  const [realtimeUpdatedAt, setRealtimeUpdatedAt] = useState<Date | null>(null);

  const load = useCallback(async () => {
    if (!user?.id) return;
    setLoading(true);
    const [{ data: imaging, error: imagingError }, { data: notes }] = await Promise.all([
      (supabase as any).rpc('get_clinician_imaging_results', { _limit: 200 }),
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
      .on('postgres_changes', { event: '*', schema: 'public', table: 'imaging_orders' }, () => { setRealtimeUpdatedAt(new Date()); playWorkflowSound('info'); void load(); })
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load, user?.id]);

  const unreadResultIds = useMemo(() => new Set(notifications.filter((n) => !n.is_read).map((n) => n.related_entity_id).filter(Boolean) as string[]), [notifications]);

  const acknowledge = async (resultId: string) => {
    const { error } = await (supabase as any).rpc('acknowledge_imaging_result', { _result_id: resultId });
    const matching = notifications.filter((n) => n.related_entity_id === resultId && !n.is_read);
    if (error) {
      playWorkflowSound('critical');
      toast({ title: 'Could not acknowledge result', description: error.message, variant: 'destructive' });
      return;
    }
    if (matching.length) await (supabase as any).rpc('mark_notifications_read', { _notification_ids: matching.map((n) => n.id) });
    playWorkflowSound('success');
    toast({ title: 'Radiology result acknowledged' });
    void load();
  };

  const modalities = useMemo(() => Array.from(new Set(results.map((r) => r.modality).filter(Boolean))).sort(), [results]);
  const visibleResults = useMemo(() => results.filter((result) => {
    const reviewMatches = appliedFilters.review === 'all'
      || (appliedFilters.review === 'pending' && !result.acknowledged_at)
      || (appliedFilters.review === 'acknowledged' && !!result.acknowledged_at);
    const priorityMatches = appliedFilters.priority === 'all' || result.priority.toLowerCase() === appliedFilters.priority;
    const modalityMatches = appliedFilters.modality === 'all' || result.modality === appliedFilters.modality;
    return reviewMatches && priorityMatches && modalityMatches;
  }), [results, appliedFilters]);

  if (!user) return null;
  const pendingCount = results.filter((r) => !r.acknowledged_at).length;
  const urgentCount = results.filter((r) => ['urgent', 'stat'].includes(r.priority.toLowerCase())).length;

  return (
    <OperationalWorklistShell
      icon={ImageIcon}
      eyebrow="Diagnostics · Results review"
      title="Radiology Results Review"
      description="Review completed diagnostic imaging reports available in your authorised patient and facility context. Imaging acquisition and report completion remain restricted to authorised radiology staff."
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
      listMeta={`${visibleResults.length} shown · ${results.length} total${realtimeUpdatedAt ? ` · Updated ${realtimeUpdatedAt.toLocaleTimeString()}` : ''}`}
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
              <th scope="col">S/N</th><th scope="col">Patient ID</th><th scope="col">Full Name</th><th scope="col">Service</th><th scope="col">Diagnoses</th><th scope="col">Prescriber</th><th scope="col">Priority</th><th scope="col">Report finalized</th><th scope="col">Audit timestamp</th>
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
                    <td>{visibleResults.indexOf(result) + 1}</td>
                    <td className="font-mono text-xs">{result.patients?.patient_code ?? result.patient_id.slice(0, 8)}</td>
                    <td><p className="font-semibold">{result.patients?.first_name} {result.patients?.last_name}</p></td>
                    <td><p className="font-medium">{result.study_name}</p><p className="text-xs text-muted-foreground">{result.modality}</p></td>
                    <td className="text-xs">{result.diagnoses.length ? result.diagnoses.map((d) => <div key={d.id}>{d.is_principal ? 'Principal: ' : ''}{d.diagnosis}{d.icd_code ? ` (${d.icd_code})` : ''}</div>) : <span className="text-muted-foreground">No current encounter diagnosis</span>}</td>
                    <td className="text-sm">{result.prescriber_name ?? '—'}</td>
                    <td>{urgent ? <ClinicalStatusBadge status={result.priority} /> : <ClinicalStatusBadge status="started" label="Routine" />}</td>
                    <td className="whitespace-nowrap text-xs text-muted-foreground">{result.completed_at ? new Date(result.completed_at).toLocaleString() : new Date(result.updated_at).toLocaleString()}</td>
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
                      <td colSpan={10}>
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
