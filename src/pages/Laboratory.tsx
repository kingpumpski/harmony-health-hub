import RefreshButton from '@/components/ui/RefreshButton';
// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { FlaskConical, CheckCircle2, ShieldCheck, LockKeyhole, Search, Plus, X } from 'lucide-react';
import { Link, useSearchParams } from 'react-router-dom';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { subscribeMasterDataChanged } from '@/lib/masterDataEvents';
import CatalogueCreateModal from '@/components/catalogue/CatalogueCreateModal';
import LabTestGroupsManager from '@/components/laboratory/LabTestGroupsManager';
import { isMissingLabResultAttachmentsApi, labResultAttachmentsUnavailableMessage } from '@/lib/labResultAttachments';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import ClinicalDataTable, { ClinicalStatusBadge, ClinicalTableAction } from '@/components/workflow/ClinicalDataTable';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string; email: string | null; gender?: string | null; date_of_birth?: string | null }
interface LabCatalogueItem {
  id: string; test_code: string; test_name: string; category: string | null; specimen_type: string | null; sample_quantity?: string | null;
  unit: string | null; reference_low: number | null; reference_high: number | null; reference_text: string | null;
  default_charge: number; active: boolean; parameters?: Array<{code:string;name?:string;label?:string;category?:string;unit?:string;reference_low?:number|null;reference_high?:number|null;reference_text?:string|null;required?:boolean;type?:string}>;
}
interface LabSpecimen {
  id: string; lab_order_id: string; accession_number: string; barcode_value: string;
  specimen_type: string | null; status: 'collected' | 'received' | 'processing' | 'rejected';
  collected_at: string; rejected_at: string | null; rejection_reason: string | null;
}
interface LabOrder {
  id: string; patient_id: string; test_name: string; test_category: string | null;
  priority: string; status: string; created_at: string; clinical_notes: string | null; lab_test_catalogue_id: string | null;
  facility_id?: string; service_order_id?: string; billing_status?: string;
  group_id?: string | null; parent_order_id?: string | null; panel_name?: string | null;
}
interface LabResult {
  id: string; lab_order_id: string; result_data: { value?: string } | null; parameter_results?: Record<string, unknown> | null; interpretation: string | null;
  is_abnormal: boolean; status: string; entered_at: string; approved_at: string | null;
  numeric_value: number | null; unit: string | null; reference_low: number | null; reference_high: number | null; abnormal_flag: string | null;
}
interface LabResultAttachment {
  id: string;
  lab_order_id: string;
  storage_path: string;
  file_name: string;
  mime_type: string;
  created_at: string;
}

function isLabOrderPaid(order: LabOrder) {
  return ['released', 'in_progress', 'completed'].includes(order.billing_status ?? '');
}

function timeAgo(value: string) {
  const minutes = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 60000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes} m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} h`;
  return `${Math.floor(hours / 24)} d`;
}

function escapeReportText(value: unknown) {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character] ?? character);
}

function hasOutOfRangeResult(
  parameters: NonNullable<LabCatalogueItem['parameters']>,
  values: Record<string, string>,
) {
  return parameters.some((parameter) => {
    if (parameter.type !== 'numeric' && parameter.type !== 'number') return false;
    const raw = values[parameter.code]?.trim();
    if (!raw) return false;
    const value = Number(raw);
    return Number.isFinite(value)
      && ((parameter.reference_low != null && value < parameter.reference_low)
        || (parameter.reference_high != null && value > parameter.reference_high));
  });
}

export default function Laboratory() {
  const { user } = useAuth();
  const [searchParams] = useSearchParams();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [catalogue, setCatalogue] = useState<LabCatalogueItem[]>([]);
  const [orders, setOrders] = useState<LabOrder[]>([]);
  const [resultsByOrder, setResultsByOrder] = useState<Record<string, LabResult>>({});
  const [attachmentsByOrder, setAttachmentsByOrder] = useState<Record<string, LabResultAttachment[]>>({});
  const [specimensByOrder, setSpecimensByOrder] = useState<Record<string, LabSpecimen[]>>({});
  const [rejectingSpecimenId, setRejectingSpecimenId] = useState<string | null>(null);
  const [specimenRejectionReason, setSpecimenRejectionReason] = useState('');
  const [rejectingSpecimen, setRejectingSpecimen] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [catalogueOpen, setCatalogueOpen] = useState(false);
  const [allowLabOrdering, setAllowLabOrdering] = useState(false);
  const [allowRadiologyOrdering, setAllowRadiologyOrdering] = useState(false);
  const [clinicalContext, setClinicalContext] = useState<Record<string, unknown> | null>(null);
  const [clinicalContextLoading, setClinicalContextLoading] = useState(false);
  const [createCatalogueOpen, setCreateCatalogueOpen] = useState(false);
  const [catalogueCharges, setCatalogueCharges] = useState<Record<string, string>>({});
  const [savingCatalogueId, setSavingCatalogueId] = useState<string | null>(null);
  const [attentionOrderId, setAttentionOrderId] = useState(searchParams.get('order') || '');
  const [attentionResultId, setAttentionResultId] = useState(searchParams.get('result') || '');
  const [loading, setLoading] = useState(false);
  const [resultFor, setResultFor] = useState<string | null>(null);
  const [resultText, setResultText] = useState('');
  const [numericValue, setNumericValue] = useState('');
  const [parameterValues, setParameterValues] = useState<Record<string, string>>({});
  const [savingResultFor, setSavingResultFor] = useState<string | null>(null);
  const [orderAction, setOrderAction] = useState<string | null>(null);
  const [interpretation, setInterpretation] = useState('');
  const [isAbnormal, setIsAbnormal] = useState(false);
  const [statusFilter, setStatusFilter] = useState('all');
  const [priorityFilter, setPriorityFilter] = useState('all');
  const [resultFilter, setResultFilter] = useState('all');
  const [appliedFilters, setAppliedFilters] = useState({ status: 'all', priority: 'all', result: 'all' });
  const [expandedOrderId, setExpandedOrderId] = useState<string | null>(null);
  const previousQueueTotal = useRef(0);
  const hasLoadedQueue = useRef(false);
  const attachmentSchemaNoticeShown = useRef(false);
  const workspaceLoadGeneration = useRef(0);
  const workspaceRequestInFlight = useRef(false);

  useEffect(() => {
    if (!user?.id) return;
    let active = true;
    void supabase.rpc('get_facility_workflow_settings').then(({ data, error }) => {
      if (!active) return;
      if (error) { setAllowLabOrdering(false); return; }
      const settings = (data ?? {}) as { allow_lab_ordering?: boolean; allow_radiology_ordering?: boolean };
      setAllowLabOrdering(Boolean(settings.allow_lab_ordering));
      setAllowRadiologyOrdering(Boolean(settings.allow_radiology_ordering));
    });
    return () => { active = false; };
  }, [user?.id]);

  const updateLabOrdering = async (enabled: boolean) => {
    const { error } = await supabase.rpc('set_facility_workflow_settings', {
      _allow_lab_ordering: enabled,
      _allow_radiology_ordering: allowRadiologyOrdering,
      _notification_settings: null,
    });
    if (error) { toast({ title: 'Workflow setting was not saved', description: error.message, variant: 'destructive' }); return; }
    setAllowLabOrdering(enabled);
    toast({ title: enabled ? 'Laboratory ordering enabled' : 'Laboratory ordering disabled', description: 'The facility workflow setting has been saved.' });
  };

  const viewClinicalContext = async (order: LabOrder) => {
    setClinicalContextLoading(true);
    setClinicalContext(null);
    const { data, error } = await supabase.rpc('get_diagnostic_order_clinical_context', { _order_id: order.id, _order_type: 'laboratory' });
    setClinicalContextLoading(false);
    if (error) { toast({ title: 'Clinical context unavailable', description: 'The encounter context could not be loaded for this facility-scoped order.', variant: 'destructive' }); return; }
    setClinicalContext((data ?? {}) as Record<string, unknown>);
  };

  const loadAll = useCallback(async () => {
    if (workspaceRequestInFlight.current || document.visibilityState !== 'visible') return;
    workspaceRequestInFlight.current = true;
    const request = ++workspaceLoadGeneration.current;
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('get_laboratory_workspace', { _limit: 300 });
      if (request !== workspaceLoadGeneration.current) return;
      if (error) {
        const offline = error.status === 503 || /failed to fetch|network|connection|\b503\b|gateway/i.test(error.message ?? '');
        toast({ title: offline ? 'Laboratory workspace offline' : 'Laboratory workspace unavailable', description: offline ? 'The database service is temporarily unavailable. Your existing data has not been changed. Retry when the connection recovers.' : error.message, variant: 'destructive' });
        return;
      }
    const workspace = (data ?? {}) as {
      patients?: Patient[];
      catalogue?: LabCatalogueItem[];
      orders?: LabOrder[];
      results?: LabResult[];
    };
    setPatients(workspace.patients ?? []);
    setCatalogue(workspace.catalogue ?? []);
    const nextOrders = workspace.orders ?? [];
    setOrders(nextOrders);
    const map: Record<string, LabResult> = {};
    (workspace.results ?? []).forEach((r) => { if (!map[r.lab_order_id]) map[r.lab_order_id] = r; });
    setResultsByOrder(map);
    if (nextOrders.length) {
      const { data: attachmentRows, error: attachmentError } = await supabase
        .from('lab_result_attachments' as never)
        .select('id,lab_order_id,storage_path,file_name,mime_type,created_at' as never)
        .in('lab_order_id' as never, nextOrders.map((order) => order.id) as never);
      if (request !== workspaceLoadGeneration.current) return;
      if (attachmentError) {
        setAttachmentsByOrder({});
        if (!isMissingLabResultAttachmentsApi(attachmentError) || !attachmentSchemaNoticeShown.current) {
          toast({
            title: 'Lab report attachments unavailable',
            description: isMissingLabResultAttachmentsApi(attachmentError)
              ? labResultAttachmentsUnavailableMessage
              : attachmentError.message,
            variant: 'destructive',
          });
        }
        if (isMissingLabResultAttachmentsApi(attachmentError)) attachmentSchemaNoticeShown.current = true;
      } else {
        setAttachmentsByOrder(((attachmentRows ?? []) as unknown as LabResultAttachment[]).reduce<Record<string, LabResultAttachment[]>>((grouped, attachment) => {
          (grouped[attachment.lab_order_id] ??= []).push(attachment);
          return grouped;
        }, {}));
      }
    } else {
      setAttachmentsByOrder({});
    }
    try {
      const { data: specimenData, error: specimenError } = await supabase.rpc('get_laboratory_specimens', { _limit: 300 } as never);
      if (request !== workspaceLoadGeneration.current) return;
      if (specimenError) {
        toast({ title: 'Specimen tracking unavailable', description: specimenError.message, variant: 'destructive' });
        setSpecimensByOrder({});
      } else {
        const specimenRows = (specimenData ?? []) as unknown as LabSpecimen[];
        setSpecimensByOrder(specimenRows.reduce<Record<string, LabSpecimen[]>>((grouped, specimen) => {
          (grouped[specimen.lab_order_id] ??= []).push(specimen);
          return grouped;
        }, {}));
      }
    } catch (specimenError) {
      toast({ title: 'Specimen tracking unavailable', description: specimenError instanceof Error ? specimenError.message : 'Retry to refresh specimen tracking.', variant: 'destructive' });
    }
    const requestedOrderId = searchParams.get('order');
    const requestedResultId = searchParams.get('result');
    if (requestedOrderId && nextOrders.some((order) => order.id === requestedOrderId)) {
      setAttentionOrderId(requestedOrderId);
    } else if (requestedResultId) {
      const matchingResult = (workspace.results ?? []).find((result) => result.id === requestedResultId);
      if (matchingResult) setAttentionOrderId(matchingResult.lab_order_id);
    }
    } catch (error) {
      if (request === workspaceLoadGeneration.current) {
        const message = error instanceof Error ? error.message : 'Check your connection and retry.';
        const offline = /failed to fetch|network|connection|\b503\b|gateway/i.test(message);
        toast({ title: offline ? 'Laboratory workspace offline' : 'Laboratory workspace unavailable', description: offline ? 'The database service is temporarily unavailable. Your existing data has not been changed. Retry when the connection recovers.' : message, variant: 'destructive' });
      }
    } finally {
      if (request === workspaceLoadGeneration.current) setLoading(false);
      workspaceRequestInFlight.current = false;
    }
  }, [searchParams]);

  useEffect(() => {
    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') void loadAll();
    };
    void loadAll();
    const unsubscribe = subscribeMasterDataChanged(['lab_tests','patients'], refreshWhenVisible);
    const refreshTimer = window.setInterval(refreshWhenVisible, 30000);
    document.addEventListener('visibilitychange', refreshWhenVisible);
    window.addEventListener('pageshow', refreshWhenVisible);
    return () => {
      workspaceLoadGeneration.current += 1;
      unsubscribe();
      window.clearInterval(refreshTimer);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
      window.removeEventListener('pageshow', refreshWhenVisible);
    };
  }, [loadAll, user?.id]);

  const counters = useMemo(() => {
    const awaitingSample = orders.filter((o) => o.status === 'ordered').length;
    const processing = orders.filter((o) => o.status === 'sample_collected').length;
    const awaitingApproval = orders.filter((o) => o.status === 'completed').length;
    const approved = orders.filter((o) => o.status === 'approved').length;
    const active = awaitingSample + processing + awaitingApproval;
    if (hasLoadedQueue.current && active > previousQueueTotal.current) playWorkflowSound('info');
    previousQueueTotal.current = active;
    hasLoadedQueue.current = true;
    return { active, awaitingSample, processing, awaitingApproval, approved };
  }, [orders]);

  const visibleOrders = useMemo(() => orders.filter((order) => {
    const result = resultsByOrder[order.id];
    const statusMatches = appliedFilters.status === 'all'
      || (appliedFilters.status === 'awaiting_payment' ? order.status !== 'cancelled' && !isLabOrderPaid(order) : order.status === appliedFilters.status);
    const priorityMatches = appliedFilters.priority === 'all' || order.priority === appliedFilters.priority;
    const resultMatches = appliedFilters.result === 'all'
      || (appliedFilters.result === 'with_result' && !!result)
      || (appliedFilters.result === 'awaiting_result' && !result)
      || (appliedFilters.result === 'abnormal' && !!result?.is_abnormal);
    const patient = patients.find((entry) => entry.id === order.patient_id);
    const labId = `LAB-${new Date(order.created_at).getFullYear()}-${order.id.replaceAll('-', '').toUpperCase()}`;
    const searchable = `${patient?.patient_code ?? ''} ${patient?.first_name ?? ''} ${patient?.last_name ?? ''} ${order.id} ${labId} ${order.test_name}`.toLowerCase();
    return statusMatches && priorityMatches && resultMatches && searchable.includes(searchTerm.trim().toLowerCase());
  }).sort((a, b) => a.patient_id.localeCompare(b.patient_id)
    || (a.parent_order_id ?? a.id).localeCompare(b.parent_order_id ?? b.id)
    || a.created_at.localeCompare(b.created_at)), [
    orders, resultsByOrder, appliedFilters, patients, searchTerm,
  ]);

  useEffect(() => {
    const orderFromUrl = searchParams.get('order');
    const resultFromUrl = searchParams.get('result');
    if (orderFromUrl) setAttentionOrderId(orderFromUrl);
    if (resultFromUrl) setAttentionResultId(resultFromUrl);
  }, [searchParams]);

  useEffect(() => {
    if (!attentionOrderId) return;
    const timer = window.setTimeout(() => {
      document.getElementById(`lab-order-${attentionOrderId}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }, 100);
    return () => window.clearTimeout(timer);
  }, [attentionOrderId, orders.length]);

  const collectSample = async (id: string) => {
    if (orderAction) return;
    setOrderAction(id);
    let error: any = null;
    try {
      ({ error } = await supabase.rpc('collect_lab_sample', { _lab_order_id: id } as never));
    } catch (requestError) {
      toast({ title: 'Could not collect sample', description: requestError instanceof Error ? requestError.message : 'Check your connection and retry.', variant: 'destructive' });
      return;
    } finally {
      setOrderAction(null);
    }
    if (error) {
      const blocked = /payment|release|approval|released/i.test(error.message);
      playWorkflowSound('error');
      toast({ title: blocked ? 'Payment approval required' : 'Could not collect sample', description: error.message, variant: 'destructive' });
      return;
    }
    playWorkflowSound('success');
    toast({ title: 'Sample collected and accessioned', description: 'A specimen accession number and barcode value have been generated.' });
    void loadAll();
  };

  const rejectSpecimen = async (specimenId: string) => {
    if (rejectingSpecimen || specimenRejectionReason.trim().length < 3) {
      if (specimenRejectionReason.trim().length < 3) toast({ title: 'Rejection reason required', description: 'Enter at least 3 characters explaining why the specimen cannot be processed.', variant: 'destructive' });
      return;
    }
    setRejectingSpecimen(true);
    try {
      const { error } = await supabase.rpc('reject_lab_specimen', {
        _specimen_id: specimenId,
        _reason: specimenRejectionReason.trim(),
      } as never);
      if (error) {
        toast({ title: 'Could not reject specimen', description: error.message, variant: 'destructive' });
        return;
      }
      playWorkflowSound('success');
      toast({ title: 'Specimen rejected', description: 'The rejection reason was recorded. The order is available for recollection.' });
      setRejectingSpecimenId(null);
      setSpecimenRejectionReason('');
      void loadAll();
    } catch (error) {
      toast({ title: 'Could not reject specimen', description: error instanceof Error ? error.message : 'Check your connection and retry.', variant: 'destructive' });
    } finally {
      setRejectingSpecimen(false);
    }
  };

  const submitResult = async (orderId: string) => {
    if (savingResultFor) return;
    const parsedNumeric = numericValue.trim() === '' ? null : Number(numericValue);
    if (numericValue.trim() !== '' && !Number.isFinite(parsedNumeric)) return toast({ title: 'Invalid numeric result', description: 'Enter a valid number or leave the numeric field empty.', variant: 'destructive' });
    setSavingResultFor(orderId);
    const order = orders.find((entry) => entry.id === orderId);
    const catalogueItem = catalogue.find((entry) => entry.id === order?.lab_test_catalogue_id);
    const parameters = catalogueItem?.parameters ?? [];
    const structuredResults = Object.fromEntries(parameters.filter((parameter) => parameter.code).map((parameter) => [parameter.code, parameterValues[parameter.code]?.trim() ?? '']));
    const hasAbnormalResult = isAbnormal || hasOutOfRangeResult(parameters, parameterValues);
    const missingRequired = parameters.find((parameter) => parameter.required && !structuredResults[parameter.code]);
    if (missingRequired) {
      setSavingResultFor(null);
      return toast({ title: 'Required result missing', description: `Enter ${missingRequired.label ?? missingRequired.name ?? missingRequired.code} before submitting.`, variant: 'destructive' });
    }
    let error: any = null;
    try {
      if (parameters.length > 0) {
        if (!Object.values(structuredResults).some((value) => value.length > 0) && !resultText.trim()) {
          setSavingResultFor(null);
          return toast({ title: 'Result required', description: 'Enter at least one structured parameter or a narrative result.', variant: 'destructive' });
        }
        ({ error } = await supabase.rpc('enter_lab_result_structured', {
          _lab_order_id: orderId,
          _parameter_results: structuredResults,
          _result_text: resultText.trim() || null,
          _interpretation: interpretation.trim() || null,
          _is_abnormal: hasAbnormalResult,
        } as never));
      } else {
        ({ error } = await supabase.rpc('enter_lab_result', {
          _lab_order_id: orderId,
          _result_text: resultText,
          _numeric_value: parsedNumeric,
          _interpretation: interpretation || null,
          _is_abnormal: hasAbnormalResult,
        } as never));
      }
    } catch (requestError) {
      toast({ title: 'Failed to save result', description: requestError instanceof Error ? requestError.message : 'Check your connection and retry.', variant: 'destructive' });
      return;
    } finally {
      setSavingResultFor(null);
    }
    if (error) return toast({ title: 'Failed to save result', description: error.message, variant: 'destructive' });
    setResultFor(null); setResultText(''); setNumericValue(''); setParameterValues({}); setInterpretation(''); setIsAbnormal(false);
    playWorkflowSound(hasAbnormalResult ? 'critical' : 'success');
    toast({ title: 'Result submitted', description: hasAbnormalResult ? 'Abnormal result flagged for clinical attention.' : 'The result is ready for clinical approval.' });
    void loadAll();
  };

  const saveResultDraft = async (orderId: string) => {
    if (savingResultFor) return;
    const order = orders.find((entry) => entry.id === orderId);
    const parameters = catalogue.find((entry) => entry.id === order?.lab_test_catalogue_id)?.parameters ?? [];
    const structuredResults = Object.fromEntries(parameters.filter((parameter) => parameter.code).map((parameter) => [parameter.code, parameterValues[parameter.code]?.trim() ?? '']));
    const hasAbnormalResult = isAbnormal || hasOutOfRangeResult(parameters, parameterValues);
    setSavingResultFor(orderId);
    try {
      const { error } = await supabase.rpc('save_lab_result_draft' as never, {
        _lab_order_id: orderId,
        _parameter_results: structuredResults,
        _result_text: resultText.trim() || null,
        _interpretation: interpretation.trim() || null,
        _is_abnormal: hasAbnormalResult,
      } as never);
      if (error) {
        toast({ title: 'Could not save result draft', description: error.message, variant: 'destructive' });
        return;
      }
      toast({ title: 'Result draft saved', description: 'It remains hidden from clinicians until laboratory approval.' });
      void loadAll();
    } catch (error) {
      toast({ title: 'Could not save result draft', description: error instanceof Error ? error.message : 'Check your connection and retry.', variant: 'destructive' });
    } finally {
      setSavingResultFor(null);
    }
  };

  const uploadResultAttachment = async (orderId: string, file?: File) => {
    if (!file) return;
    if (!['application/pdf', 'image/jpeg', 'image/png'].includes(file.type) || file.size > 15 * 1024 * 1024) {
      toast({ title: 'Unsupported attachment', description: 'Upload a PDF, JPG or PNG file up to 15 MB.', variant: 'destructive' });
      return;
    }
    const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
    const path = `${orderId}/${crypto.randomUUID()}-${safeName}`;
    const order = orders.find((entry) => entry.id === orderId);
    if (!order?.facility_id || !user?.id) {
      toast({ title: 'Attachment upload unavailable', description: 'The released order facility context is missing. Refresh the worklist and retry.', variant: 'destructive' });
      return;
    }
    const { error: uploadError } = await supabase.storage.from('lab-result-attachments').upload(path, file, { contentType: file.type, upsert: false });
    if (uploadError) {
      toast({ title: 'Attachment upload failed', description: uploadError.message, variant: 'destructive' });
      return;
    }
    const { error: metadataError } = await supabase.from('lab_result_attachments' as never).insert({
      lab_order_id: orderId,
      lab_result_id: resultsByOrder[orderId]?.id ?? null,
      facility_id: order.facility_id,
      storage_path: path,
      file_name: file.name,
      mime_type: file.type,
      file_size_bytes: file.size,
      uploaded_by: user.id,
    } as never);
    if (metadataError) {
      await supabase.storage.from('lab-result-attachments').remove([path]);
      toast({
        title: 'Attachment record failed',
        description: isMissingLabResultAttachmentsApi(metadataError)
          ? labResultAttachmentsUnavailableMessage
          : metadataError.message,
        variant: 'destructive',
      });
      return;
    }
    if (!order) return;
    toast({ title: 'Report attachment uploaded' });
    void loadAll();
  };

  const openResultAttachment = async (path: string) => {
    const { data, error } = await supabase.storage.from('lab-result-attachments').createSignedUrl(path, 60);
    if (error) {
      toast({ title: 'Could not open attachment', description: error.message, variant: 'destructive' });
      return;
    }
    window.open(data.signedUrl, '_blank', 'noopener,noreferrer');
  };

  const printPanelReport = (parentOrderId: string) => {
    const panelOrders = orders.filter((order) => order.parent_order_id === parentOrderId);
    if (!panelOrders.length) return;
    const firstOrder = panelOrders[0];
    const patient = patients.find((entry) => entry.id === firstOrder.patient_id);
    const sections = panelOrders.map((order) => {
      const test = catalogue.find((item) => item.id === order.lab_test_catalogue_id);
      const result = resultsByOrder[order.id];
      const parameters = test?.parameters ?? [];
      const rows = parameters.map((parameter) => {
        const value = result?.parameter_results?.[parameter.code] ?? '';
        const number = Number(value);
        const flag = value === '' ? '—'
          : parameter.type === 'numeric' || parameter.type === 'number'
            ? Number.isFinite(number) && parameter.reference_low != null && number < parameter.reference_low ? 'Low'
              : Number.isFinite(number) && parameter.reference_high != null && number > parameter.reference_high ? 'High' : 'Normal'
            : '—';
        const range = parameter.reference_text ?? `${parameter.reference_low ?? '—'} – ${parameter.reference_high ?? '—'}`;
        return `<tr><td>${escapeReportText(parameter.label ?? parameter.name ?? parameter.code)}</td><td>${escapeReportText(value || '—')}</td><td>${escapeReportText(parameter.unit ?? '—')}</td><td>${escapeReportText(range)}</td><td>${escapeReportText(flag)}</td></tr>`;
      }).join('');
      return `<section><h2>${escapeReportText(order.test_name)} <small>(${escapeReportText(order.status)})</small></h2>${parameters.length
        ? `<table><thead><tr><th>Parameter</th><th>Result</th><th>Unit</th><th>Reference range</th><th>Flag</th></tr></thead><tbody>${rows}</tbody></table>`
        : `<p>${escapeReportText(result?.result_data?.value ?? 'Result not recorded')}</p>`}<p class="graph-placeholder">Instrument graph / attachment: included with the test record when available.</p></section>`;
    }).join('');
    const printWindow = window.open('', '_blank');
    if (!printWindow) {
      toast({ title: 'Print window blocked', description: 'Allow pop-ups for this application and try again.', variant: 'destructive' });
      return;
    }
    printWindow.opener = null;
    printWindow.document.write(`<!doctype html><html><head><title>${escapeReportText(firstOrder.panel_name ?? 'Laboratory panel')}</title><style>
      body{font:13px Arial,sans-serif;color:#111;margin:28px}header{border-bottom:2px solid #234;padding-bottom:12px;margin-bottom:20px}
      h1{font-size:22px;margin:0 0 8px}h2{font-size:16px;margin:24px 0 8px}small{font-weight:normal;text-transform:capitalize}
      dl{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}dt{font-size:11px;color:#555}dd{margin:3px 0 0;font-weight:bold}
      table{width:100%;border-collapse:collapse}th,td{border:1px solid #aaa;padding:6px;text-align:left}th{background:#eee}
      .graph-placeholder{border:1px dashed #999;color:#555;padding:12px;font-size:11px}
      footer{border-top:1px solid #aaa;margin-top:30px;padding-top:10px;font-size:11px}
      @media print{button{display:none}}
    </style></head><body><header><h1>${escapeReportText(firstOrder.panel_name ?? 'Laboratory panel')}</h1>
    <dl><div><dt>Patient ID</dt><dd>${escapeReportText(patient?.patient_code ?? firstOrder.patient_id)}</dd></div>
    <div><dt>Patient name</dt><dd>${escapeReportText(patient ? `${patient.first_name} ${patient.last_name}` : 'Patient')}</dd></div>
    <div><dt>Gender</dt><dd>${escapeReportText(patient?.gender ?? '—')}</dd></div>
    <div><dt>Sample / Lab ID</dt><dd>${escapeReportText(firstOrder.id)}</dd></div>
    <div><dt>Department</dt><dd>Laboratory</dd></div><div><dt>Run / print time</dt><dd>${escapeReportText(new Date().toLocaleString())}</dd></div></dl></header>
    ${sections}<footer><p>Delivered by: ${escapeReportText(user?.email ?? 'Laboratory')} · Operator / Validator: recorded in each individual test approval audit.</p><p>Printed: ${escapeReportText(new Date().toLocaleString())}</p></footer></body></html>`);
    printWindow.document.close();
    window.setTimeout(() => { printWindow.focus(); printWindow.print(); }, 250);
  };

  const openResultEntry = (orderId: string) => {
    const existing = resultsByOrder[orderId];
    setResultFor(orderId);
    setResultText(existing?.parameter_results && Object.keys(existing.parameter_results).length
      ? '' : existing?.result_data?.value ?? '');
    setNumericValue(existing?.numeric_value == null ? '' : String(existing.numeric_value));
    setParameterValues(Object.fromEntries(Object.entries(existing?.parameter_results ?? {}).map(([key, value]) => [key, String(value ?? '')])));
    setInterpretation(existing?.interpretation ?? '');
    setIsAbnormal(existing?.is_abnormal ?? false);
  };

  const hasUnsavedResultValues = () => Boolean(resultText.trim() || numericValue.trim() || interpretation.trim()
    || Object.values(parameterValues).some((value) => value.trim()));

  const closeResultEntry = () => {
    if (hasUnsavedResultValues() && !window.confirm('Discard unsaved result values? Save a draft first to keep them.')) return;
    setResultFor(null);
    setResultText('');
    setNumericValue('');
    setParameterValues({});
    setInterpretation('');
    setIsAbnormal(false);
  };

  const openPanelResultEntry = (parentOrderId: string) => {
    const next = orders.find((order) => order.parent_order_id === parentOrderId && order.status === 'sample_collected');
    if (!next) {
      toast({ title: 'No panel test is ready for results', description: 'Collect a sample for a panel test before opening report entry.', variant: 'destructive' });
      return;
    }
    openResultEntry(next.id);
  };

  const switchPanelResultTab = (orderId: string) => {
    if (orderId === resultFor || savingResultFor) return;
    if (hasUnsavedResultValues() && !window.confirm('Discard the unsaved values on this test and switch to another panel test? Save a draft first to keep them.')) return;
    openResultEntry(orderId);
  };

  if (searchParams.get('view') === 'panels') {
    return <LabTestGroupsManager catalogue={catalogue} />;
  }

  const approveResult = async (resultId: string, orderId: string, patientId: string) => {
    if (orderAction) return;
    setOrderAction(orderId);
    let error: any = null;
    try {
      ({ error } = await supabase.rpc('approve_lab_result', { _lab_result_id: resultId } as never));
    } catch (requestError) {
      toast({ title: 'Approval failed', description: requestError instanceof Error ? requestError.message : 'Check your connection and retry.', variant: 'destructive' });
      return;
    } finally {
      setOrderAction(null);
    }
    if (error) {
      playWorkflowSound('error');
      return toast({ title: 'Approval failed', description: error.message, variant: 'destructive' });
    }
    const patient = patients.find((p) => p.id === patientId);
    if (patient?.email) {
      try { await supabase.functions.invoke('notify-lab-result', { body: { patientEmail: patient.email, patientName: `${patient.first_name} ${patient.last_name}`, testName: orders.find((o) => o.id === orderId)?.test_name ?? 'Lab Test' } }); }
      catch (e) { console.warn('Email notification failed', e); }
    }
    playWorkflowSound('success');
    toast({ title: 'Result approved', description: 'Patient notified by email if available.' });
    void loadAll();
  };

  const saveCatalogueCharge = async (catalogueId: string) => {
    const charge = Number(catalogueCharges[catalogueId]);
    if (!Number.isFinite(charge) || charge < 0) {
      toast({ title: 'Invalid tariff', description: 'Enter a non-negative price.', variant: 'destructive' });
      return;
    }
    setSavingCatalogueId(catalogueId);
    try {
      const { error } = await supabase.rpc('update_lab_test_catalogue_charge' as never, {
        _catalogue_id: catalogueId,
        _default_charge: charge,
      } as never);
      if (error) {
        toast({ title: 'Could not update tariff', description: error.message, variant: 'destructive' });
        return;
      }
      setCatalogue((items) => items.map((item) => item.id === catalogueId ? { ...item, default_charge: charge } : item));
      toast({ title: 'Catalogue tariff updated' });
    } catch (error) {
      toast({ title: 'Could not update tariff', description: error instanceof Error ? error.message : 'Check your connection and retry.', variant: 'destructive' });
    } finally {
      setSavingCatalogueId(null);
    }
  };

  const reportOrder = orders.find((order) => order.id === resultFor);
  const reportPatient = reportOrder && patients.find((patient) => patient.id === reportOrder.patient_id);
  const reportCatalogueItem = reportOrder && catalogue.find((item) => item.id === reportOrder.lab_test_catalogue_id);

  return (
    <>
      {!resultFor && <OperationalWorklistShell
        icon={FlaskConical}
        eyebrow="Diagnostics · Laboratory"
        title="Laboratory Workspace"
        description="Manage laboratory orders from catalogue selection through payment release, specimen collection, structured results, approval and clinical notification."
        actions={(
          <>
            {user?.roles.some((role) => ['admin', 'it_admin', 'lab_technician'].includes(role)) && (
              <button type="button" onClick={() => setCatalogueOpen(true)} className="btn-secondary inline-flex items-center gap-2">
                <FlaskConical className="h-4 w-4" aria-hidden="true" /> Test catalogue
              </button>
            )}
            <RefreshButton onClick={() => void loadAll()} loading={loading} label="Refresh laboratory workspace" />
          </>
        )}
        counters={[
          { label: 'Active orders', value: counters.active, tone: 'text-primary', surface: 'bg-primary/5' },
          { label: 'Awaiting sample', value: counters.awaitingSample, tone: 'text-warning', surface: 'bg-warning/5' },
          { label: 'Processing', value: counters.processing, tone: 'text-info', surface: 'bg-info/5' },
          { label: 'Results to approve', value: counters.awaitingApproval, tone: 'text-critical', surface: 'bg-critical/5' },
          { label: 'Approved / recent', value: counters.approved, tone: 'text-success', surface: 'bg-success/5' },
        ]}
        beforeList={(
          <div className="space-y-3">
            <Link to="/laboratory?view=panels" className="btn-secondary inline-flex items-center gap-2 text-xs">
              <FlaskConical className="h-4 w-4" aria-hidden="true" /> Manage laboratory panels
            </Link>
            {user?.roles?.includes('admin') && <section className="rounded-xl border border-border bg-card p-3 text-sm"><label className="flex items-center gap-2"><input type="checkbox" checked={allowLabOrdering} onChange={(event) => void updateLabOrdering(event.target.checked)} /><span className="font-medium">Allow laboratory ordering at this facility</span></label><p className="mt-1 text-xs text-muted-foreground">Disabled by default. Saving requires facility administrator access.</p></section>}
            <section className="flex items-start gap-3 rounded-2xl border border-primary/20 bg-primary/5 p-4" role="status">
              <LockKeyhole className="mt-0.5 h-5 w-5 shrink-0 text-primary" aria-hidden="true" />
              <p className="text-sm text-foreground">Lab orders are generated from Clinician Encounters. Only orders released by Accounts can be collected or processed. Facility-configured laboratory ordering is currently <strong>{allowLabOrdering ? 'enabled' : 'disabled'}</strong>.</p>
            </section>
            <label className="relative block max-w-xl">
              <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" aria-hidden="true" />
              <input value={searchTerm} onChange={(event) => setSearchTerm(event.target.value)} className="input-medical w-full pl-9" placeholder="Search patient name, patient ID, test or Lab ID" aria-label="Search laboratory worklist" />
            </label>
          </div>
        )}
        listTitle="Laboratory results & worklist"
        listDescription="Orders, specimen progress, result state and approval actions are presented in one clinical table."
        listMeta={`${orders.length} order${orders.length === 1 ? '' : 's'}`}
        loading={false}
        empty={false}
        listContent={(
          <ClinicalDataTable
            title="Laboratory results"
            description="Filter by clinical workflow state, priority and result availability. Use the action column for the next authorised laboratory step."
            meta={`${visibleOrders.length} shown · ${orders.length} total order${orders.length === 1 ? '' : 's'}, including payment-gated orders`}
            filters={[
              { label: 'Order status', value: statusFilter, onChange: setStatusFilter, options: [{ value: 'all', label: 'All statuses' }, { value: 'awaiting_payment', label: 'Pending payment' }, { value: 'ordered', label: 'Active / ordered' }, { value: 'sample_collected', label: 'In progress' }, { value: 'completed', label: 'Completed' }, { value: 'approved', label: 'Approved' }, { value: 'cancelled', label: 'Cancelled' }] },
              { label: 'Priority', value: priorityFilter, onChange: setPriorityFilter, options: [{ value: 'all', label: 'All priorities' }, { value: 'routine', label: 'Routine' }, { value: 'urgent', label: 'Urgent' }, { value: 'stat', label: 'STAT' }] },
              { label: 'Result state', value: resultFilter, onChange: setResultFilter, options: [{ value: 'all', label: 'All results' }, { value: 'with_result', label: 'Result entered' }, { value: 'awaiting_result', label: 'Awaiting result' }, { value: 'abnormal', label: 'Abnormal results' }] },
            ]}
            onSearch={() => setAppliedFilters({ status: statusFilter, priority: priorityFilter, result: resultFilter })}
            loading={loading}
            empty={false}
          >
            <thead>
              <tr><th scope="col">Patient ID</th><th scope="col">Patient name</th><th scope="col">Status</th><th scope="col">Test name</th><th scope="col">Lab ID</th><th scope="col">Ordered</th><th scope="col" className="text-right">Actions</th></tr>
            </thead>
            <tbody>
              {visibleOrders.map((o, orderIndex) => {
                const p = patients.find((x) => x.id === o.patient_id);
                const result = resultsByOrder[o.id];
                const item = catalogue.find((x) => x.id === o.lab_test_catalogue_id);
                return (
                  <Fragment key={o.id}>
                    {(orderIndex === 0 || visibleOrders[orderIndex - 1].patient_id !== o.patient_id) && (
                      <tr className="bg-muted/30"><td colSpan={7} className="py-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                        Patient group · {p ? `${p.first_name} ${p.last_name}` : 'Patient'} · {visibleOrders.filter((entry) => entry.patient_id === o.patient_id).length} test(s)
                      </td></tr>
                    )}
                    {o.parent_order_id && (orderIndex === 0 || visibleOrders[orderIndex - 1].parent_order_id !== o.parent_order_id) && (
                      (() => {
                        const panelTests = orders.filter((entry) => entry.parent_order_id === o.parent_order_id);
                        const panelComplete = panelTests.length > 0 && panelTests.every((entry) => entry.status === 'approved');
                        const panelPaid = panelTests.length > 0 && panelTests.every(isLabOrderPaid);
                        return <tr className="bg-primary/5"><td colSpan={7} className="py-2 text-xs font-semibold text-primary">
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="rounded-full border border-primary/20 px-2 py-0.5">Panel</span>
                            <span>{o.panel_name ?? 'Laboratory panel'}</span>
                            <span className="font-normal text-muted-foreground">{panelTests.length} tests · billed as one panel</span>
                            <span className={`rounded-full px-2 py-0.5 ${panelComplete ? 'bg-success/10 text-success' : 'bg-warning/10 text-warning'}`}>{panelComplete ? 'Completed' : 'In process'}</span>
                            <button type="button" disabled={!panelPaid} onClick={() => openPanelResultEntry(o.parent_order_id!)} className="btn-ghost text-xs disabled:cursor-not-allowed disabled:opacity-50" title={!panelPaid ? 'Accounts must release payment before result entry' : undefined}>Open panel report</button>
                            <button type="button" onClick={() => printPanelReport(o.parent_order_id!)} className="btn-ghost ml-auto text-xs">Print panel report</button>
                          </div>
                        </td></tr>;
                      })()
                    )}
                    <tr id={`lab-order-${o.id}`} className={!isLabOrderPaid(o) ? 'bg-muted/50 opacity-80' : attentionOrderId === o.id ? 'bg-primary/5' : undefined}>
                      <td className="font-mono text-xs">{p?.patient_code ?? o.patient_id.slice(0, 8).toUpperCase()}</td>
                      <td className="font-medium">{p ? `${p.first_name} ${p.last_name}` : 'Patient record'}</td>
                      <td><ClinicalStatusBadge status={!isLabOrderPaid(o) && o.status !== 'cancelled' ? 'awaiting_payment' : o.status} /></td>
                      <td>
                        <div className="min-w-[180px]">
                          <p className="font-medium">{o.test_name}</p>
                          <p className="mt-0.5 text-xs text-muted-foreground">{o.panel_name ? `${o.panel_name} panel · ` : ''}{o.test_category ?? 'Uncategorised'}{item?.specimen_type ? ` · ${item.specimen_type}` : ''}</p>
                        </div>
                      </td>
                      <td className="font-mono text-xs">LAB-{new Date(o.created_at).getFullYear()}-{o.id.replaceAll('-', '').toUpperCase()}</td>
                      <td className="whitespace-nowrap text-xs text-muted-foreground" title={new Date(o.created_at).toLocaleString()}>{timeAgo(o.created_at)}</td>
                      <td>
                        <div className="flex min-w-[220px] flex-wrap justify-end gap-2">
                          <button type="button" className="btn-secondary text-xs" onClick={() => void viewClinicalContext(o)}>View Context</button>
                          <ClinicalTableAction label={expandedOrderId === o.id ? 'Hide details' : 'View result'} onClick={() => setExpandedOrderId(expandedOrderId === o.id ? null : o.id)} />
                          {o.status === 'cancelled' ? <span className="text-xs text-muted-foreground">Cancelled</span> : isLabOrderPaid(o) ? <>
                            {o.status === 'ordered' && <ClinicalTableAction label={orderAction === o.id ? 'Collecting…' : 'Collect sample'} onClick={() => void collectSample(o.id)} />}
                            {o.status === 'sample_collected' && <ClinicalTableAction label="Enter result" icon="acknowledge" onClick={() => { setExpandedOrderId(o.id); openResultEntry(o.id); }} />}
                            {o.status === 'completed' && result && <ClinicalTableAction label={orderAction === o.id ? 'Approving…' : 'Approve'} icon="acknowledge" onClick={() => void approveResult(result.id, o.id, o.patient_id)} />}
                          </> : <span className="text-xs font-medium text-muted-foreground">Awaiting payment — actions locked</span>}
                        </div>
                      </td>
                    </tr>
                    {expandedOrderId === o.id && (
                      <tr key={`${o.id}-details`} className="bg-muted/20">
                        <td colSpan={7}>
                          <div className="grid gap-4 lg:grid-cols-[1fr_1fr]">
                            <section className="rounded-xl border border-primary/20 bg-primary/5 p-4 lg:col-span-2">
                              <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-wide text-primary">Laboratory report workspace</p><h3 className="mt-1 text-lg font-semibold">{o.test_name}</h3></div><ClinicalStatusBadge status={result?.status ?? o.status} /></div>
                              <div className="mt-3 grid gap-2 text-xs sm:grid-cols-2 lg:grid-cols-4">
                                <p><span className="text-muted-foreground">Patient ID</span><br /><strong>{p?.patient_code ?? o.patient_id}</strong></p>
                                <p><span className="text-muted-foreground">Patient name</span><br /><strong>{p ? `${p.first_name} ${p.last_name}` : 'Patient record'}</strong></p>
                                <p><span className="text-muted-foreground">Gender / age</span><br /><strong>{p?.gender ?? '—'}{p?.date_of_birth ? ` · ${Math.max(0, Math.floor((Date.now() - new Date(p.date_of_birth).getTime()) / 31557600000))} years` : ''}</strong></p>
                                <p><span className="text-muted-foreground">Sample / run</span><br /><strong>{specimensByOrder[o.id]?.[0]?.accession_number ?? 'Accession pending'} · {new Date().toLocaleString()}</strong></p>
                              </div>
                            </section>
                            <section className="rounded-xl border border-border bg-background p-4">
                              <div className="flex items-center justify-between gap-3">
                                <div>
                                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Clinical result</p>
                                  <p className="mt-1 font-medium">{o.test_name}</p>
                                </div>
                                <ClinicalStatusBadge status={result?.status ?? o.status} />
                              </div>
                              <div className="mt-3 rounded-lg border border-border p-3">
                                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Specimen accession & traceability</p>
                                {(specimensByOrder[o.id] ?? []).length === 0 ? (
                                  <p className="mt-2 text-sm text-muted-foreground">No specimen accession has been recorded.</p>
                                ) : (
                                  <div className="mt-2 space-y-2">
                                    {(specimensByOrder[o.id] ?? []).map((specimen) => (
                                      <div key={specimen.id} className="rounded-md bg-muted/30 p-2 text-sm">
                                        <div className="flex flex-wrap items-center justify-between gap-2">
                                          <span className="font-semibold">{specimen.accession_number}</span>
                                          <ClinicalStatusBadge status={specimen.status} />
                                        </div>
                                        <p className="mt-1 text-xs text-muted-foreground">Barcode value: {specimen.barcode_value}</p>
                                        <p className="text-xs text-muted-foreground">Type: {specimen.specimen_type ?? 'Not specified'} · Collected: {new Date(specimen.collected_at).toLocaleString()}</p>
                                        {specimen.rejection_reason && <p className="mt-1 text-xs text-critical">Rejected: {specimen.rejection_reason}</p>}
                                        {specimen.status !== 'rejected' && o.status === 'sample_collected' && (user?.roles.some((role) => ['admin','it_admin','lab_technician'].includes(role))) && (
                                          <button type="button" className="btn-ghost mt-2 text-xs" disabled={rejectingSpecimen} onClick={() => { setRejectingSpecimenId(rejectingSpecimenId === specimen.id ? null : specimen.id); setSpecimenRejectionReason(''); }}>Reject specimen</button>
                                        )}
                                        {rejectingSpecimenId === specimen.id && (
                                          <div className="mt-2 space-y-2">
                                            <textarea value={specimenRejectionReason} onChange={(event) => setSpecimenRejectionReason(event.target.value)} maxLength={1000} rows={2} className="input-medical w-full" placeholder="Required rejection reason (3–1000 characters)" aria-label="Specimen rejection reason" />
                                            <div className="flex gap-2">
                                              <button type="button" disabled={rejectingSpecimen || specimenRejectionReason.trim().length < 3} className="btn-primary text-xs disabled:opacity-60" onClick={() => void rejectSpecimen(specimen.id)}>{rejectingSpecimen ? 'Recording…' : 'Confirm rejection'}</button>
                                              <button type="button" disabled={rejectingSpecimen} className="btn-ghost text-xs" onClick={() => { setRejectingSpecimenId(null); setSpecimenRejectionReason(''); }}>Cancel</button>
                                            </div>
                                          </div>
                                        )}
                                      </div>
                                    ))}
                                  </div>
                                )}
                              </div>
                              <div className="mt-3 rounded-lg border border-border p-3">
                                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Attached report documents</p>
                                {(attachmentsByOrder[o.id] ?? []).length ? (
                                  <ul className="mt-2 space-y-1">{(attachmentsByOrder[o.id] ?? []).map((attachment) => (
                                    <li key={attachment.id}><button type="button" onClick={() => void openResultAttachment(attachment.storage_path)} className="text-sm font-medium text-primary hover:underline">{attachment.file_name}</button><span className="ml-2 text-xs text-muted-foreground">{new Date(attachment.created_at).toLocaleString()}</span></li>
                                  ))}</ul>
                                ) : <p className="mt-2 text-sm text-muted-foreground">No report documents attached.</p>}
                              </div>
                              {result ? (
                                <div className="mt-3 space-y-1 text-sm">
                                  <p><strong>Value:</strong> {result.numeric_value !== null ? `${result.numeric_value}${result.unit ? ` ${result.unit}` : ''}` : (result.result_data?.value ?? '—')}</p>
                                  {(result.reference_low !== null || result.reference_high !== null) && <p><strong>Reference:</strong> {result.reference_low ?? '—'} – {result.reference_high ?? '—'}{result.unit ? ` ${result.unit}` : ''}</p>}
                                  {result.parameter_results && Object.keys(result.parameter_results).length > 0 && <dl className="mt-2 space-y-1 border-t border-border pt-2">{Object.entries(result.parameter_results).map(([code, value]) => <div key={code} className="flex flex-wrap justify-between gap-2"><dt className="text-muted-foreground">{code}</dt><dd className="font-medium break-all">{typeof value === 'object' ? JSON.stringify(value) : String(value ?? '—')}</dd></div>)}</dl>}
                                  {result.interpretation && <p><strong>Interpretation:</strong> {result.interpretation}</p>}
                                  {result.is_abnormal && <p className="mt-2 inline-flex items-center rounded-full bg-critical/10 px-2.5 py-1 text-xs font-semibold text-critical">Abnormal result · clinical attention required</p>}
                                </div>
                              ) : <p className="mt-3 text-sm text-muted-foreground">No result has been entered for this laboratory order.</p>}
                            </section>
                            <section className="rounded-xl border border-border bg-background p-4">
                              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Workflow action</p>
                              {resultFor === o.id && o.status === 'sample_collected' && isLabOrderPaid(o) ? (
                                <div className="mt-3 space-y-2">
                                  {item?.parameters && item.parameters.length > 0 && (
                                    <div className="overflow-x-auto rounded-lg border border-border">
                                      <table className="w-full min-w-[42rem] text-left text-xs">
                                        <thead className="bg-muted/40 text-muted-foreground"><tr><th className="p-2">Parameter</th><th className="p-2">Unit</th><th className="p-2">Result value</th><th className="p-2">Reference range</th><th className="p-2">Flag</th></tr></thead>
                                        <tbody className="divide-y divide-border">
                                          {item.parameters.filter((parameter) => parameter.code).map((parameter, parameterIndex, parameters) => {
                                            const entered = parameterValues[parameter.code] ?? '';
                                            const numeric = Number(entered);
                                            const numericType = parameter.type === 'numeric' || parameter.type === 'number';
                                            const flag = !entered.trim() ? '—'
                                              : numericType && Number.isFinite(numeric) && parameter.reference_low != null && numeric < parameter.reference_low ? 'Low'
                                                : numericType && Number.isFinite(numeric) && parameter.reference_high != null && numeric > parameter.reference_high ? 'High'
                                                  : 'Normal';
                                            const category = parameter.category?.trim() || 'Test parameters';
                                            const priorCategory = parameters[parameterIndex - 1]?.category?.trim() || 'Test parameters';
                                            return (
                                              <Fragment key={parameter.code}>
                                                {parameterIndex === 0 || category !== priorCategory ? <tr className="bg-primary/5"><th colSpan={5} className="px-2 py-1.5 text-left font-semibold uppercase tracking-wide text-primary">{category}</th></tr> : null}
                                                <tr>
                                                  <td className="p-2 font-medium">{parameter.label ?? parameter.name ?? parameter.code}{parameter.required ? ' *' : ''}</td>
                                                  <td className="p-2 text-muted-foreground">{parameter.unit ?? '—'}</td>
                                                  <td className="p-2"><input id={`lab-param-${o.id}-${parameter.code}`} value={entered} onChange={(event) => setParameterValues((current) => ({ ...current, [parameter.code]: event.target.value }))} className="input-medical w-full" inputMode={numericType ? 'decimal' : 'text'} aria-required={Boolean(parameter.required)} aria-label={`${parameter.label ?? parameter.name ?? parameter.code} result`} /></td>
                                                  <td className="p-2 text-muted-foreground">{parameter.reference_text ?? `${parameter.reference_low ?? '—'} – ${parameter.reference_high ?? '—'}`}</td>
                                                  <td className={`p-2 font-semibold ${flag === 'High' || flag === 'Low' ? 'text-critical' : 'text-success'}`}>{flag}</td>
                                                </tr>
                                              </Fragment>
                                            );
                                          })}
                                        </tbody>
                                      </table>
                                    </div>
                                  )}
                                  <div className="grid gap-2 sm:grid-cols-2">
                                    <input value={numericValue} onChange={(e) => setNumericValue(e.target.value)} className="input-medical w-full" inputMode="decimal" placeholder={item?.unit ? `Single numeric result (${item.unit})` : 'Single numeric result (optional for structured tests)'} aria-label="Numeric result" />
                                    {item?.unit && <div className="input-medical bg-muted/30 text-sm flex items-center">Unit: {item.unit}</div>}
                                  </div>
                                  <textarea value={resultText} onChange={(e) => setResultText(e.target.value)} className="input-medical w-full" rows={2} placeholder="Result values / narrative" aria-label="Result values or narrative" />
                                  <input value={interpretation} onChange={(e) => setInterpretation(e.target.value)} className="input-medical w-full" placeholder="Interpretation" aria-label="Result interpretation" />
                                  <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={isAbnormal} onChange={(e) => setIsAbnormal(e.target.checked)} /> Abnormal result</label>
                                  <label className="block text-xs font-medium">Upload attachment (PDF, JPG or PNG, max 15 MB)<input type="file" accept="application/pdf,image/jpeg,image/png" className="input-medical mt-1 w-full" onChange={(event) => { void uploadResultAttachment(o.id, event.currentTarget.files?.[0]); event.currentTarget.value = ''; }} /></label>
                                  <div className="flex flex-wrap gap-2"><button type="button" disabled={savingResultFor === o.id} onClick={() => void saveResultDraft(o.id)} className="btn-secondary text-xs disabled:opacity-60">Save draft</button><button type="button" disabled={savingResultFor === o.id} onClick={() => void submitResult(o.id)} className="btn-primary text-xs disabled:opacity-60">{savingResultFor === o.id ? 'Saving…' : 'Submit result for approval'}</button><button type="button" disabled={savingResultFor === o.id} onClick={closeResultEntry} className="btn-ghost text-xs disabled:opacity-60">Cancel</button></div>
                                </div>
                              ) : (
                                <div className="mt-3 flex flex-wrap gap-2">
                                  {o.status === 'ordered' && <button type="button" onClick={() => void collectSample(o.id)} className="btn-secondary text-xs">Collect sample</button>}
                                  {o.status === 'sample_collected' && <button type="button" onClick={() => openResultEntry(o.id)} className="btn-primary text-xs">Enter result</button>}
                                  {o.status === 'completed' && result && <button type="button" onClick={() => void approveResult(result.id, o.id, o.patient_id)} className="btn-primary text-xs inline-flex items-center gap-1"><ShieldCheck className="w-3 h-3" aria-hidden="true" /> Approve & notify</button>}
                                  {o.status === 'approved' && <span className="text-xs text-success inline-flex items-center gap-1"><CheckCircle2 className="w-3 h-3" aria-hidden="true" /> Approved</span>}
                                </div>
                              )}
                              {attentionResultId === result?.id && <p className="mt-3 rounded-lg border border-primary/20 bg-primary/5 px-3 py-2 text-xs text-primary">Opened from a clinical result notification. Review this result and complete the authorised workflow action.</p>}
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
      </OperationalWorklistShell>}
      {clinicalContextLoading && <div className="fixed inset-0 z-[85] grid place-items-center bg-background/70 p-4" role="status">Loading clinical context…</div>}
      {clinicalContext && <div className="fixed inset-0 z-[85] overflow-y-auto bg-slate-950/55 p-4" role="dialog" aria-modal="true" aria-labelledby="lab-context-title"><section className="mx-auto mt-8 max-w-2xl rounded-2xl border border-border bg-background p-5 shadow-2xl"><header className="flex items-start justify-between gap-3"><div><h2 id="lab-context-title" className="text-lg font-semibold">Clinical context</h2><p className="text-sm text-muted-foreground">Read-only context from the originating encounter.</p></div><button type="button" className="btn-ghost" onClick={() => setClinicalContext(null)} aria-label="Close clinical context">×</button></header><dl className="mt-4 grid gap-3 text-sm"><div><dt className="text-xs text-muted-foreground">Patient</dt><dd className="font-medium">{String(clinicalContext.patient_name ?? '—')}</dd></div><div><dt className="text-xs text-muted-foreground">Chief complaint</dt><dd className="whitespace-pre-wrap">{String(clinicalContext.chief_complaint ?? 'Not recorded')}</dd></div><div><dt className="text-xs text-muted-foreground">Diagnosis</dt><dd className="whitespace-pre-wrap">{String(clinicalContext.diagnosis ?? 'Not recorded')}</dd></div><div><dt className="text-xs text-muted-foreground">Clinical notes</dt><dd className="whitespace-pre-wrap">{String(clinicalContext.clinical_notes ?? 'No linked clinical notes')}</dd></div></dl><div className="mt-5 flex justify-end"><button type="button" className="btn-primary" onClick={() => setClinicalContext(null)}>Close</button></div></section></div>}
      {resultFor && reportOrder && (
        <main className="fixed inset-0 z-[75] overflow-y-auto bg-background p-4 sm:p-7" aria-labelledby="lab-report-entry-title">
          <div className="mx-auto max-w-6xl space-y-5">
            <header className="rounded-2xl border border-border bg-card p-5 shadow-sm">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div><p className="text-xs font-semibold uppercase tracking-wider text-primary">Diagnostics · Structured report</p><h1 id="lab-report-entry-title" className="mt-1 text-2xl font-semibold">{reportOrder.test_name}</h1><p className="mt-1 text-sm text-muted-foreground">Enter and verify measured values before submitting the report to the approval queue.</p></div>
                <div className="flex gap-2"><button type="button" onClick={closeResultEntry} className="btn-secondary">Back to worklist</button><ClinicalStatusBadge status={reportOrder.status} /></div>
              </div>
              {reportOrder.parent_order_id && <nav className="mt-4 flex flex-wrap gap-2 border-t border-border pt-4" aria-label={`${reportOrder.panel_name ?? 'Panel'} test results`}>
                {orders.filter((order) => order.parent_order_id === reportOrder.parent_order_id).map((order) => (
                  <button key={order.id} type="button" disabled={order.status !== 'sample_collected' || Boolean(savingResultFor)}
                    onClick={() => switchPanelResultTab(order.id)}
                    className={`rounded-xl border px-3 py-2 text-left text-xs disabled:cursor-not-allowed disabled:opacity-50 ${resultFor === order.id ? 'border-primary bg-primary/5 text-primary' : 'border-border'}`}>
                    <span className="block font-medium">{order.test_name}</span><span className="mt-1 block capitalize">{order.status.replaceAll('_', ' ')}</span>
                  </button>
                ))}
              </nav>}
              <dl className="mt-5 grid gap-3 rounded-xl bg-muted/30 p-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
                <div><dt className="text-xs text-muted-foreground">Patient ID</dt><dd className="mt-1 font-medium">{reportPatient?.patient_code ?? reportOrder.patient_id}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Patient name</dt><dd className="mt-1 font-medium">{reportPatient ? `${reportPatient.first_name} ${reportPatient.last_name}` : 'Patient record'}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Gender / age</dt><dd className="mt-1 font-medium">{reportPatient?.gender ?? '—'}{reportPatient?.date_of_birth ? ` · ${Math.max(0, Math.floor((Date.now() - new Date(reportPatient.date_of_birth).getTime()) / 31557600000))} years` : ''}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Sample ID</dt><dd className="mt-1 font-medium">{specimensByOrder[reportOrder.id]?.[0]?.accession_number ?? 'Accession pending'}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Department</dt><dd className="mt-1 font-medium">Laboratory</dd></div>
                <div><dt className="text-xs text-muted-foreground">Ordered</dt><dd className="mt-1 font-medium">{new Date(reportOrder.created_at).toLocaleString()}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Run time</dt><dd className="mt-1 font-medium">{new Date().toLocaleString()}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Lab ID</dt><dd className="mt-1 break-all font-mono text-xs">LAB-{new Date(reportOrder.created_at).getFullYear()}-{reportOrder.id.replaceAll('-', '').toUpperCase()}</dd></div>
              </dl>
            </header>
            <section className="rounded-2xl border border-border bg-card p-5 shadow-sm">
              {reportCatalogueItem?.parameters?.length ? (
                <div className="overflow-x-auto rounded-xl border border-border">
                  <table className="w-full min-w-[48rem] text-left text-sm">
                    <thead className="bg-muted/40 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="p-3">Parameter</th><th className="p-3">Unit</th><th className="p-3">Result value</th><th className="p-3">Reference range</th><th className="p-3">Flag</th></tr></thead>
                    <tbody className="divide-y divide-border">{reportCatalogueItem.parameters.filter((parameter) => parameter.code).map((parameter) => {
                      const entered = parameterValues[parameter.code] ?? '';
                      const numericType = parameter.type === 'numeric' || parameter.type === 'number';
                      const numeric = Number(entered);
                      const flag = !entered.trim() ? '—'
                        : numericType && Number.isFinite(numeric) && parameter.reference_low != null && numeric < parameter.reference_low ? 'Low'
                          : numericType && Number.isFinite(numeric) && parameter.reference_high != null && numeric > parameter.reference_high ? 'High'
                            : 'Normal';
                      return <tr key={parameter.code}><td className="p-3 font-medium">{parameter.label ?? parameter.name ?? parameter.code}{parameter.required ? ' *' : ''}{parameter.category && <span className="block text-xs font-normal text-muted-foreground">{parameter.category}</span>}</td><td className="p-3 text-muted-foreground">{parameter.unit ?? '—'}</td><td className="p-3"><input value={entered} onChange={(event) => setParameterValues((current) => ({ ...current, [parameter.code]: event.target.value }))} inputMode={numericType ? 'decimal' : 'text'} aria-label={`${parameter.label ?? parameter.name ?? parameter.code} result`} className="input-medical w-full" /></td><td className="p-3 text-muted-foreground">{parameter.reference_text ?? `${parameter.reference_low ?? '—'} – ${parameter.reference_high ?? '—'}`}</td><td className={`p-3 font-semibold ${flag === 'High' || flag === 'Low' ? 'text-critical' : 'text-success'}`}>{flag}</td></tr>;
                    })}</tbody>
                  </table>
                </div>
              ) : (
                <div className="grid gap-3 sm:grid-cols-2">
                  <label className="text-sm font-medium">Numeric result<input value={numericValue} onChange={(event) => setNumericValue(event.target.value)} inputMode="decimal" className="input-medical mt-1 w-full" /></label>
                  <label className="text-sm font-medium">Unit<input value={reportCatalogueItem?.unit ?? ''} readOnly className="input-medical mt-1 w-full bg-muted/30" /></label>
                </div>
              )}
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <label className="text-sm font-medium sm:col-span-2">Narrative result / comments<textarea value={resultText} onChange={(event) => setResultText(event.target.value)} className="input-medical mt-1 w-full" rows={3} /></label>
                <label className="text-sm font-medium sm:col-span-2">Interpretation<input value={interpretation} onChange={(event) => setInterpretation(event.target.value)} className="input-medical mt-1 w-full" /></label>
                <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={isAbnormal} onChange={(event) => setIsAbnormal(event.target.checked)} /> Clinically abnormal finding</label>
                <label className="text-sm font-medium">Upload document (PDF, JPG, PNG)<input type="file" accept="application/pdf,image/jpeg,image/png" className="input-medical mt-1 w-full" onChange={(event) => { void uploadResultAttachment(reportOrder.id, event.currentTarget.files?.[0]); event.currentTarget.value = ''; }} /></label>
              </div>
              <div className="mt-5 flex flex-wrap justify-end gap-2 border-t border-border pt-4">
                <button type="button" disabled={savingResultFor === reportOrder.id} onClick={() => void saveResultDraft(reportOrder.id)} className="btn-secondary disabled:opacity-60">Save draft</button>
                <button type="button" disabled={savingResultFor === reportOrder.id} onClick={() => void submitResult(reportOrder.id)} className="btn-primary disabled:opacity-60">{savingResultFor === reportOrder.id ? 'Saving…' : 'Submit for approval'}</button>
              </div>
              <p className="mt-3 text-xs text-muted-foreground">Submitting marks this individual test as completed and places it in the laboratory approval queue. Other tests for the same patient remain independently in progress.</p>
            </section>
          </div>
        </main>
      )}
      {catalogueOpen && (
        <div className="fixed inset-0 z-[80] overflow-y-auto bg-slate-950/55 p-3 backdrop-blur-sm sm:p-6" role="dialog" aria-modal="true" aria-labelledby="lab-catalogue-title">
          <section className="mx-auto my-4 max-w-5xl rounded-2xl border border-border bg-background p-5 shadow-2xl sm:p-6">
            <header className="flex items-start justify-between gap-3">
              <div><p className="text-xs font-semibold uppercase tracking-wider text-primary">Diagnostics · Master data</p><h2 id="lab-catalogue-title" className="mt-1 text-xl font-semibold">Laboratory test catalogue</h2><p className="mt-1 text-sm text-muted-foreground">Maintain test definitions and tariffs. Tariff changes are written to the system audit log.</p></div>
              <button type="button" onClick={() => setCatalogueOpen(false)} className="btn-ghost" aria-label="Close catalogue"><X className="h-4 w-4" /></button>
            </header>
            <div className="mt-4 flex justify-end">
              <button type="button" onClick={() => setCreateCatalogueOpen(true)} className="btn-primary inline-flex items-center gap-2"><Plus className="h-4 w-4" /> Add laboratory test</button>
            </div>
            <div className="mt-4 overflow-x-auto rounded-xl border border-border">
              <table className="w-full min-w-[38rem] text-left text-sm">
                <thead className="bg-muted/40 text-xs text-muted-foreground"><tr><th className="px-3 py-2">Test</th><th className="px-3 py-2">Sample</th><th className="px-3 py-2">Parameters</th><th className="px-3 py-2">Tariff (GHS)</th><th className="px-3 py-2">Save</th></tr></thead>
                <tbody className="divide-y divide-border">{catalogue.map((item) => (
                  <tr key={item.id}>
                    <td className="px-3 py-3"><p className="font-medium">{item.test_name}</p><p className="text-xs text-muted-foreground">{item.test_code} · {item.category ?? 'Uncategorised'}</p></td>
                    <td className="px-3 py-3 text-xs text-muted-foreground">{item.specimen_type ?? 'Not set'}{item.sample_quantity ? ` · ${item.sample_quantity}` : ''}</td>
                    <td className="px-3 py-3 text-xs text-muted-foreground">{item.parameters?.length ?? 0} parameter(s)</td>
                    <td className="px-3 py-3"><input aria-label={`Tariff for ${item.test_name}`} type="number" min="0" step="0.01" value={catalogueCharges[item.id] ?? String(item.default_charge)} onChange={(event) => setCatalogueCharges((current) => ({ ...current, [item.id]: event.target.value }))} className="input-medical w-32" /></td>
                    <td className="px-3 py-3"><button type="button" disabled={savingCatalogueId === item.id} onClick={() => void saveCatalogueCharge(item.id)} className="btn-secondary text-xs disabled:opacity-60">{savingCatalogueId === item.id ? 'Saving…' : 'Update tariff'}</button></td>
                  </tr>
                ))}{catalogue.length === 0 && <tr><td colSpan={5} className="p-6 text-center text-sm text-muted-foreground">No active tests are configured.</td></tr>}</tbody>
              </table>
            </div>
          </section>
        </div>
      )}
      {catalogueOpen && createCatalogueOpen && (
        <CatalogueCreateModal
          kind="lab"
          initialName=""
          userRoles={user?.roles ?? []}
          userPermissions={user?.permissions ?? []}
          userDepartment={user?.department}
          onCreated={(created) => {
            setCreateCatalogueOpen(false);
            setCatalogue((items) => [...items, created as LabCatalogueItem].sort((a, b) => a.test_name.localeCompare(b.test_name)));
            toast({ title: 'Laboratory test added to catalogue' });
          }}
          onClose={() => setCreateCatalogueOpen(false)}
        />
      )}
    </>
  );
}
