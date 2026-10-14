// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { CheckCircle2, FlaskConical, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import ClinicalDataTable, { ClinicalProgressBar, ClinicalStatusBadge, ClinicalTableAction } from '@/components/workflow/ClinicalDataTable';
import {
  isMissingLabResultAttachmentsTable,
  isNetworkFetchError,
  databaseFeatureUpdatingMessage,
  laboratoryNetworkUnavailableMessage,
} from '@/lib/labResultAttachments';

interface LabReportRow {
  id: string;
  lab_order_id: string;
  patient_id: string;
  encounter_id: string | null;
  test_name: string;
  test_category: string | null;
  priority: string;
  clinical_notes: string | null;
  result_data: { value?: string } | null;
  parameter_results: Record<string, unknown> | null;
  result_text: string | null;
  interpretation: string | null;
  is_abnormal: boolean;
  status: string;
  entered_at: string;
  approved_at: string | null;
  acknowledged_at: string | null;
  acknowledged_by: string | null;
  prescriber_name: string | null;
  diagnoses: Array<{ id: string; diagnosis: string; icd_code: string | null; is_principal: boolean }>;
  numeric_value: number | null;
  unit: string | null;
  reference_low: number | null;
  reference_high: number | null;
  abnormal_flag: string | null;
  patients?: { id: string; first_name: string; last_name: string; patient_code: string } | null;
  panel_name?: string | null;
  panel_tests?: Array<{ id: string; test_name: string; status: string }>;
}
interface LabReportAttachment {
  id: string;
  lab_order_id: string;
  storage_path: string;
  file_name: string;
}

export default function LaboratoryResults() {
  const { user } = useAuth();
  const [results, setResults] = useState<LabReportRow[]>([]);
  const [attachmentsByResult, setAttachmentsByResult] = useState<Record<string, LabReportAttachment[]>>({});
  const [loading, setLoading] = useState(true);
  const [priorityFilter, setPriorityFilter] = useState('all');
  const [interpretationFilter, setInterpretationFilter] = useState('all');
  const [appliedFilters, setAppliedFilters] = useState({ priority: 'all', interpretation: 'all' });
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [realtimeUpdatedAt, setRealtimeUpdatedAt] = useState<Date | null>(null);
  const attachmentSchemaNoticeShown = useRef(false);
  const networkNoticeShown = useRef(false);

  const load = useCallback(async () => {
    if (!user?.id) {
      setResults([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
    const { data, error } = await (supabase as any).rpc('get_clinician_lab_results', { _limit: 200 });
    if (error) {
      setResults([]);
      if (!isNetworkFetchError(error) || !networkNoticeShown.current) {
        toast({
          title: 'Approved laboratory reports unavailable',
          description: isNetworkFetchError(error) ? laboratoryNetworkUnavailableMessage : error.message,
          variant: 'destructive',
        });
      }
      if (isNetworkFetchError(error)) networkNoticeShown.current = true;
    } else {
      networkNoticeShown.current = false;
      const rows = (data ?? []) as LabReportRow[];
      setResults(rows);
      const labOrderIds = [...new Set(rows.map((result) => result.lab_order_id))];
      if (labOrderIds.length) {
        const { data: attachments, error: attachmentError } = await supabase.rpc('get_lab_result_attachments' as never, {
          _lab_order_ids: labOrderIds,
        } as never);
        if (attachmentError) {
          setAttachmentsByResult({});
          const missingSchema = isMissingLabResultAttachmentsTable(attachmentError);
          if (missingSchema) console.error('[laboratory-results] get_lab_result_attachments RPC is unavailable:', attachmentError);
          if (!missingSchema || !attachmentSchemaNoticeShown.current) {
            toast({
              title: 'Report attachments unavailable',
              description: missingSchema ? databaseFeatureUpdatingMessage : attachmentError.message,
              variant: missingSchema ? 'default' : 'destructive',
            });
          }
          if (missingSchema) attachmentSchemaNoticeShown.current = true;
        } else {
          setAttachmentsByResult(((attachments ?? []) as unknown as LabReportAttachment[]).reduce<Record<string, LabReportAttachment[]>>((grouped, attachment) => {
            (grouped[attachment.lab_order_id] ??= []).push(attachment);
            return grouped;
          }, {}));
        }
      } else {
        setAttachmentsByResult({});
      }
    }
    } catch (error) {
      setResults([]);
      if (!isNetworkFetchError(error) || !networkNoticeShown.current) {
        toast({
          title: 'Approved laboratory reports unavailable',
          description: isNetworkFetchError(error)
            ? laboratoryNetworkUnavailableMessage
            : error instanceof Error ? error.message : 'Check your connection and retry.',
          variant: 'destructive',
        });
      }
      if (isNetworkFetchError(error)) networkNoticeShown.current = true;
    }
    setLoading(false);
  }, [user?.id]);

  useEffect(() => {
    void load();
    if (!user?.id) return;
    const channel = supabase.channel(`lab-results-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'lab_results' }, () => { setRealtimeUpdatedAt(new Date()); void load(); })
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load, user?.id]);

  const visibleResults = useMemo(() => results.filter((result) => {
    const priorityMatches = appliedFilters.priority === 'all'
      || result.priority.toLowerCase() === appliedFilters.priority;
    const interpretationMatches = appliedFilters.interpretation === 'all'
      || (appliedFilters.interpretation === 'abnormal' && result.is_abnormal)
      || (appliedFilters.interpretation === 'normal' && !result.is_abnormal);
    return priorityMatches && interpretationMatches;
  }), [results, appliedFilters]);

  const acknowledge = async (resultId: string) => {
    const { error } = await (supabase as any).rpc('acknowledge_lab_result', { _result_id: resultId });
    if (error) { toast({ title: 'Could not acknowledge result', description: error.message, variant: 'destructive' }); return; }
    toast({ title: 'Laboratory result acknowledged' });
    void load();
  };

  const openAttachment = async (path: string) => {
    const { data, error } = await supabase.storage.from('lab-result-attachments').createSignedUrl(path, 60);
    if (error) {
      toast({ title: 'Could not open report attachment', description: error.message, variant: 'destructive' });
      return;
    }
    window.open(data.signedUrl, '_blank', 'noopener,noreferrer');
  };

  const abnormalCount = results.filter((result) => result.is_abnormal).length;
  const urgentCount = results.filter((result) => ['urgent', 'stat'].includes(result.priority.toLowerCase())).length;

  if (!user) return null;

  return (
    <OperationalWorklistShell
      icon={FlaskConical}
      eyebrow="Diagnostics · Clinical report review"
      title="Laboratory Results"
      description="Read approved laboratory results relevant to your authorised patient and facility context. Result entry, specimen collection, approval and laboratory operations remain restricted to authorised laboratory staff."
      actions={(
        <button
          type="button"
          onClick={() => void load()}
          disabled={loading}
          className="btn-secondary inline-flex items-center gap-2"
          aria-label="Refresh approved laboratory results"
        >
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" />
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      )}
      counters={[
        { label: 'Approved reports', value: results.length, tone: 'text-success', surface: 'bg-success/5' },
        { label: 'Abnormal results', value: abnormalCount, tone: 'text-critical', surface: 'bg-critical/5' },
        { label: 'Urgent / STAT', value: urgentCount, tone: 'text-warning', surface: 'bg-warning/5' },
      ]}
      listTitle="Approved laboratory reports"
      listDescription="This is a read-only clinical results view. Pending orders and unapproved results are not included."
      listMeta={`${visibleResults.length} shown · ${results.length} approved${realtimeUpdatedAt ? ` · Updated ${realtimeUpdatedAt.toLocaleTimeString()}` : ''}`}
      loading={loading}
      empty={visibleResults.length === 0}
      emptyTitle="No approved laboratory results"
      emptyDescription="Approved reports for your authorised patient/facility context will appear here."
      listContent={(
        <ClinicalDataTable
          title="Approved laboratory results"
          description="Review verified values, reference ranges and interpretation before continuing the patient's care plan."
          meta={`${visibleResults.length} report${visibleResults.length === 1 ? '' : 's'}`}
          filters={[
            { label: 'Clinical priority', value: priorityFilter, onChange: setPriorityFilter, options: [{ value: 'all', label: 'All priorities' }, { value: 'routine', label: 'Routine' }, { value: 'urgent', label: 'Urgent' }, { value: 'stat', label: 'STAT' }] },
            { label: 'Result interpretation', value: interpretationFilter, onChange: setInterpretationFilter, options: [{ value: 'all', label: 'All results' }, { value: 'normal', label: 'No abnormal flag' }, { value: 'abnormal', label: 'Abnormal results' }] },
          ]}
          onSearch={() => setAppliedFilters({ priority: priorityFilter, interpretation: interpretationFilter })}
          loading={loading}
          empty={visibleResults.length === 0}
          emptyMessage="No approved laboratory reports match the selected filters."
        >
          <thead>
            <tr>
              <th scope="col">S/N</th><th scope="col">Patient ID</th><th scope="col">Full Name</th><th scope="col">Service</th><th scope="col">Diagnoses</th><th scope="col">Prescriber</th><th scope="col">Result</th><th scope="col">Status</th><th scope="col">Approved</th>
              <th scope="col" className="text-right">Action</th>
            </tr>
          </thead>
          <tbody>
            {visibleResults.map((result) => {
              const priority = result.priority.toLowerCase();
              const resultValue = result.numeric_value !== null
                ? `${result.numeric_value}${result.unit ? ` ${result.unit}` : ''}`
                : result.result_text ?? result.result_data?.value ?? 'Result recorded';
              return (
                <Fragment key={result.id}>
                  <tr className={result.is_abnormal ? 'bg-critical/5' : undefined}>
                    <td>{visibleResults.indexOf(result) + 1}</td><td className="font-mono text-xs">{result.patients?.patient_code ?? result.patient_id.slice(0, 8)}</td><td><p className="font-semibold">{result.patients?.first_name} {result.patients?.last_name}</p></td><td><p className="font-medium">{result.test_name}</p><p className="text-xs text-muted-foreground">{result.panel_name ? `${result.panel_name} panel · ` : ''}{result.test_category ?? 'Laboratory'}</p></td><td className="text-xs">{result.diagnoses.length ? result.diagnoses.map((d) => <div key={d.id}>{d.is_principal ? 'Principal: ' : ''}{d.diagnosis}{d.icd_code ? ` (${d.icd_code})` : ''}</div>) : <span className="text-muted-foreground">No current encounter diagnosis</span>}</td><td className="text-sm">{result.prescriber_name ?? '—'}</td>
                    <td>{['urgent', 'stat'].includes(priority) ? <ClinicalStatusBadge status={priority} label={priority.toUpperCase()} /> : <ClinicalStatusBadge status="started" label="Routine" />}</td>
                    <td>
                      <div className="min-w-[140px]">
                        <p className={`font-semibold ${result.is_abnormal ? 'text-critical' : ''}`}>{resultValue}</p>
                        {result.is_abnormal && <p className="mt-0.5 text-xs font-medium text-critical">{result.abnormal_flag ?? 'Abnormal result'}</p>}
                      </div>
                    </td>
                    <td><ClinicalStatusBadge status={result.acknowledged_at ? 'acknowledged' : 'approved'} /></td><td className="whitespace-nowrap text-xs text-muted-foreground">{result.approved_at ? new Date(result.approved_at).toLocaleString() : 'Approval timestamp unavailable'}</td><td>
                      <div className="flex min-w-[140px] justify-end">
                        <ClinicalTableAction label={expandedId === result.id ? 'Hide report' : 'View report'} onClick={() => setExpandedId(expandedId === result.id ? null : result.id)} />
                        {!result.acknowledged_at && <ClinicalTableAction label="Acknowledge" icon="acknowledge" onClick={() => void acknowledge(result.id)} />}
                      </div>
                    </td>
                  </tr>
                  {expandedId === result.id && (
                    <tr key={`${result.id}-details`} className="bg-muted/20">
                      <td colSpan={10}>
                        <div className="grid gap-3 lg:grid-cols-2">
                          <section className="rounded-xl border border-border bg-background p-4">
                            <div className="flex items-center justify-between gap-2">
                              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Verified result</p>
                              <ClinicalStatusBadge status="approved" />
                            </div>
                            <p className="mt-2 text-sm font-semibold">{result.test_name}</p>
                            {result.panel_name && <p className="mt-1 text-xs text-primary">Part of {result.panel_name} panel</p>}
                            {result.panel_tests && result.panel_tests.length > 0 && <section className="mt-3 rounded-lg border border-border p-3">
                              <h3 className="text-xs font-semibold">Panel test progress</h3>
                              <ul className="mt-2 space-y-1">{result.panel_tests.map((test) => <li key={test.id} className="flex items-center justify-between gap-3 text-xs"><span>{test.test_name}</span><ClinicalStatusBadge status={test.status} /></li>)}</ul>
                            </section>}
                            <p className="mt-2 text-sm">{resultValue}</p>
                            {(result.reference_low !== null || result.reference_high !== null) && (
                              <p className="mt-1 text-xs text-muted-foreground">
                                Reference range: {result.reference_low ?? '—'} – {result.reference_high ?? '—'}{result.unit ? ` ${result.unit}` : ''}
                              </p>
                            )}
                            {result.parameter_results && Object.keys(result.parameter_results).length > 0 && (
                              <dl className="mt-3 grid gap-2 sm:grid-cols-2">
                                {Object.entries(result.parameter_results).map(([name, value]) => (
                                  <div key={name} className="rounded-lg bg-muted/40 p-2">
                                    <dt className="text-xs text-muted-foreground">{name.replaceAll('_', ' ')}</dt>
                                    <dd className="mt-0.5 break-words text-sm font-medium">{typeof value === 'string' || typeof value === 'number' ? value : JSON.stringify(value)}</dd>
                                  </div>
                                ))}
                              </dl>
                            )}
                            <div className="mt-4 border-t border-border pt-3">
                              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Report attachments</p>
                              {(attachmentsByResult[result.lab_order_id] ?? []).length ? (
                                <ul className="mt-2 space-y-1">{attachmentsByResult[result.lab_order_id].map((attachment) => <li key={attachment.id}><button type="button" onClick={() => void openAttachment(attachment.storage_path)} className="text-sm font-medium text-primary hover:underline">{attachment.file_name}</button></li>)}</ul>
                              ) : <p className="mt-1 text-xs text-muted-foreground">No attachments were supplied.</p>}
                            </div>
                          </section>
                          <section className="rounded-xl border border-border bg-background p-4">
                            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Clinical interpretation</p>
                            {result.interpretation ? <p className="mt-2 whitespace-pre-wrap text-sm">{result.interpretation}</p> : <p className="mt-2 text-sm text-muted-foreground">No interpretation was recorded.</p>}
                            {result.clinical_notes && <p className="mt-3 text-sm"><span className="font-semibold">Ordering notes:</span> {result.clinical_notes}</p>}
                            {result.is_abnormal && <p className="mt-3 rounded-lg border border-critical/20 bg-critical/5 px-3 py-2 text-sm text-critical">Abnormal result: review in clinical context and document the appropriate care plan.</p>}
                            <div className="mt-4 flex items-center gap-2 text-xs text-success"><CheckCircle2 className="h-4 w-4" aria-hidden="true" /> Approved by the authorised laboratory workflow</div>
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
    />
  );
}
