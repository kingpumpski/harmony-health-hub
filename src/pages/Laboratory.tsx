import RefreshButton from '@/components/ui/RefreshButton';
// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import { searchPatientDirectory } from '@/lib/patientDirectory';
import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { FlaskConical, Plus, CheckCircle2, ShieldCheck, AlertTriangle, LockKeyhole, BellRing} from 'lucide-react';
import { Link, useSearchParams } from 'react-router-dom';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { subscribeMasterDataChanged } from '@/lib/masterDataEvents';
import CatalogueCreateModal from '@/components/catalogue/CatalogueCreateModal';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import ClinicalDataTable, { ClinicalProgressBar, ClinicalStatusBadge, ClinicalTableAction } from '@/components/workflow/ClinicalDataTable';

interface Patient { id: string; first_name: string; last_name: string; patient_code: string; email: string | null }
interface LabCatalogueItem {
  id: string; test_code: string; test_name: string; category: string | null; specimen_type: string | null;
  unit: string | null; reference_low: number | null; reference_high: number | null; reference_text: string | null;
  default_charge: number; active: boolean; parameters?: Array<{code:string;name?:string;label?:string;unit?:string;reference_low?:number|null;reference_high?:number|null;reference_text?:string|null;required?:boolean;type?:string}>;
}
interface EncounterOption { id: string; patient_id: string; created_at: string; status: string; principal_diagnosis: string | null; }
interface LabSpecimen {
  id: string; lab_order_id: string; accession_number: string; barcode_value: string;
  specimen_type: string | null; status: 'collected' | 'received' | 'processing' | 'rejected';
  collected_at: string; rejected_at: string | null; rejection_reason: string | null;
}
interface LabOrder {
  id: string; patient_id: string; test_name: string; test_category: string | null;
  priority: string; status: string; created_at: string; clinical_notes: string | null; lab_test_catalogue_id: string | null;
}
interface LabResult {
  id: string; lab_order_id: string; result_data: { value?: string } | null; parameter_results?: Record<string, unknown> | null; interpretation: string | null;
  is_abnormal: boolean; status: string; entered_at: string; approved_at: string | null;
  numeric_value: number | null; unit: string | null; reference_low: number | null; reference_high: number | null; abnormal_flag: string | null;
}

export default function Laboratory() {
  const { user } = useAuth();
  const [searchParams] = useSearchParams();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [catalogue, setCatalogue] = useState<LabCatalogueItem[]>([]);
  const [orders, setOrders] = useState<LabOrder[]>([]);
  const [resultsByOrder, setResultsByOrder] = useState<Record<string, LabResult>>({});
  const [specimensByOrder, setSpecimensByOrder] = useState<Record<string, LabSpecimen[]>>({});
  const [rejectingSpecimenId, setRejectingSpecimenId] = useState<string | null>(null);
  const [specimenRejectionReason, setSpecimenRejectionReason] = useState('');
  const [rejectingSpecimen, setRejectingSpecimen] = useState(false);
  const [pid, setPid] = useState(searchParams.get('patient') || '');
  const [encounterId, setEncounterId] = useState(searchParams.get('encounter') || '');
  const [encounters, setEncounters] = useState<EncounterOption[]>([]);
  const [catalogueId, setCatalogueId] = useState('');
  const [catalogueSearch, setCatalogueSearch] = useState('');
  const [createLabTestName, setCreateLabTestName] = useState('');
  const [testName, setTestName] = useState('');
  const [category, setCategory] = useState('');
  const [priority, setPriority] = useState('routine');
  const [notes, setNotes] = useState('');
  const [amount, setAmount] = useState('');
  const [attentionOrderId, setAttentionOrderId] = useState(searchParams.get('order') || '');
  const [attentionResultId, setAttentionResultId] = useState(searchParams.get('result') || '');
  const [loading, setLoading] = useState(false);
  const [resultFor, setResultFor] = useState<string | null>(null);
  const [resultText, setResultText] = useState('');
  const [numericValue, setNumericValue] = useState('');
  const [parameterValues, setParameterValues] = useState<Record<string, string>>({});
  const [savingResultFor, setSavingResultFor] = useState<string | null>(null);
  const [orderAction, setOrderAction] = useState<string | null>(null);
  const [creatingOrder, setCreatingOrder] = useState(false);
  const [interpretation, setInterpretation] = useState('');
  const [isAbnormal, setIsAbnormal] = useState(false);
  const [statusFilter, setStatusFilter] = useState('all');
  const [priorityFilter, setPriorityFilter] = useState('all');
  const [resultFilter, setResultFilter] = useState('all');
  const [appliedFilters, setAppliedFilters] = useState({ status: 'all', priority: 'all', result: 'all' });
  const [expandedOrderId, setExpandedOrderId] = useState<string | null>(null);
  const previousQueueTotal = useRef(0);
  const hasLoadedQueue = useRef(false);
  const workspaceLoadGeneration = useRef(0);
  const workspaceRequestInFlight = useRef(false);

  const loadAll = async () => {
    if (workspaceRequestInFlight.current || document.visibilityState !== 'visible') return;
    workspaceRequestInFlight.current = true;
    const request = ++workspaceLoadGeneration.current;
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('get_laboratory_workspace', { _limit: 300 });
      if (request !== workspaceLoadGeneration.current) return;
      if (error) {
        toast({ title: 'Laboratory workspace unavailable', description: error.message, variant: 'destructive' });
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
        toast({ title: 'Laboratory workspace unavailable', description: error instanceof Error ? error.message : 'Check your connection and retry.', variant: 'destructive' });
      }
    } finally {
      if (request === workspaceLoadGeneration.current) setLoading(false);
      workspaceRequestInFlight.current = false;
    }
  };

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
  }, [user?.id]);

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

  useEffect(() => {
    const patientFromUrl = searchParams.get('patient');
    const encounterFromUrl = searchParams.get('encounter');
    const orderFromUrl = searchParams.get('order');
    const resultFromUrl = searchParams.get('result');
    if (patientFromUrl) setPid(patientFromUrl);
    if (encounterFromUrl) setEncounterId(encounterFromUrl);
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

  useEffect(() => {
    let active = true;
    const loadEncounters = async () => {
      if (!pid) {
        setEncounters([]);
        return;
      }
      const { data, error } = await supabase
        .from('encounters')
        .select('id,patient_id,created_at,status,principal_diagnosis')
        .eq('patient_id', pid)
        .neq('status', 'cancelled')
        .order('created_at', { ascending: false })
        .limit(20);
      if (!active) return;
      if (error) {
        setEncounters([]);
        toast({ title: 'Encounter context unavailable', description: error.message, variant: 'destructive' });
        return;
      }
      setEncounters((data ?? []) as EncounterOption[]);
      if (encounterId && !(data ?? []).some((item) => item.id === encounterId)) setEncounterId('');
    };
    void loadEncounters();
    return () => { active = false; };
  }, [pid]);

  const canCreateCatalogue = user?.roles.some((role) => role === 'admin' || role === 'it_admin') || user?.permissions.includes('create_items') || user?.permissions.includes('create_services');
  const filteredCatalogue = useMemo(() => catalogue.filter((item) => `${item.test_code} ${item.test_name} ${item.category ?? ''}`.toLowerCase().includes(catalogueSearch.toLowerCase())), [catalogue, catalogueSearch]);

  const selectTest = (id: string) => {
    setCatalogueId(id);
    const item = catalogue.find((entry) => entry.id === id);
    if (!item) return;
    setTestName(item.test_name);
    setCategory(item.category ?? '');
    setAmount(String(item.default_charge));
  };

  const createOrder = async (e: React.FormEvent) => {
    e.preventDefault();
    if (creatingOrder) return;
    const numericAmount = Number(amount);
    if (!pid || !testName || !Number.isFinite(numericAmount) || numericAmount < 0) {
      toast({ title: 'Complete the order details', description: 'Patient, test and a valid amount are required.', variant: 'destructive' });
      return;
    }
    setCreatingOrder(true);
    let data: any = null;
    let error: any = null;
    try {
      ({ data, error } = await supabase.rpc('create_lab_order_with_catalogue_atomic', {
        _patient_id: pid, _test_name: testName, _test_category: category || null,
        _priority: priority, _clinical_notes: notes || null, _amount: numericAmount, _encounter_id: encounterId || null,
        _catalogue_id: catalogueId || null,
      } as never));
    } catch (requestError) {
      toast({ title: 'Failed to create lab order', description: requestError instanceof Error ? requestError.message : 'Check your connection and retry.', variant: 'destructive' });
      return;
    } finally {
      setCreatingOrder(false);
    }
    if (error) {
      playWorkflowSound('error');
      toast({ title: 'Failed to create lab order', description: error.message, variant: 'destructive' });
      return;
    }
    setPid(''); setEncounterId(''); setEncounters([]); setCatalogueId(''); setCatalogueSearch(''); setTestName(''); setCategory(''); setNotes(''); setPriority('routine'); setAmount('');
    playWorkflowSound('success');
    toast({ title: numericAmount > 0 ? 'Lab order sent to Accounts' : 'Lab order created', description: numericAmount > 0 ? 'Laboratory work remains blocked until Accounts releases it.' : 'The order is available to the laboratory workflow.' });
    void loadAll();
  };

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
          _is_abnormal: isAbnormal,
        } as never));
      } else {
        ({ error } = await supabase.rpc('enter_lab_result', {
          _lab_order_id: orderId,
          _result_text: resultText,
          _numeric_value: parsedNumeric,
          _interpretation: interpretation || null,
          _is_abnormal: isAbnormal,
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
    playWorkflowSound(isAbnormal ? 'critical' : 'success');
    toast({ title: 'Result submitted', description: isAbnormal ? 'Abnormal result flagged for clinical attention.' : 'The result is ready for clinical approval.' });
    void loadAll();
  };

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

  return (
    <>
      <OperationalWorklistShell
        icon={FlaskConical}
        eyebrow="Diagnostics · Laboratory"
        title="Laboratory Workspace"
        description="Manage laboratory orders from catalogue selection through payment release, specimen collection, structured results, approval and clinical notification."
        actions={(
          <>
            <Link to="/notifications" className="btn-ghost inline-flex items-center gap-2 w-fit">
              <BellRing className="w-4 h-4" aria-hidden="true" /> Notifications
            </Link>
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
          <section className="card-medical p-5">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" aria-hidden="true" /> New laboratory order</h2>
                <p className="mt-1 text-xs text-muted-foreground">Attach the originating encounter when applicable. Server-side validation remains authoritative for patient, encounter and payment boundaries.</p>
              </div>
              <span className="rounded-full border border-primary/20 bg-primary/5 px-2.5 py-1 text-[10px] font-medium text-primary">Diagnostic workflow</span>
            </div>
            <form onSubmit={createOrder} className="mt-4 grid gap-3 lg:grid-cols-3">
              <div>
                <label htmlFor="lab-patient" className="mb-1 block text-xs font-semibold">Patient <span className="text-critical">*</span></label>
                <select id="lab-patient" value={pid} onChange={(e) => { setPid(e.target.value); setEncounterId(''); }} className="input-medical w-full" required>
                  <option value="">Select patient…</option>
                  {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} · {p.patient_code}</option>)}
                </select>
              </div>
              <div>
                <label htmlFor="lab-encounter" className="mb-1 block text-xs font-semibold">Originating encounter</label>
                <select id="lab-encounter" value={encounterId} onChange={(e) => setEncounterId(e.target.value)} className="input-medical w-full" disabled={!pid}>
                  <option value="">Attach to encounter (optional)</option>
                  {encounters.map((item) => <option key={item.id} value={item.id}>{new Date(item.created_at).toLocaleDateString()} · {item.principal_diagnosis || item.status}</option>)}
                </select>
              </div>
              <div>
                <label htmlFor="lab-catalogue-search" className="mb-1 block text-xs font-semibold">Test catalogue search</label>
                <input id="lab-catalogue-search" value={catalogueSearch} onChange={(e) => setCatalogueSearch(e.target.value)} className="input-medical w-full" placeholder="Search laboratory test catalogue" />
              </div>
              <div>
                <label htmlFor="lab-catalogue" className="mb-1 block text-xs font-semibold">Catalogue test</label>
                <select id="lab-catalogue" value={catalogueId} onChange={(e) => selectTest(e.target.value)} className="input-medical w-full">
                  <option value="">Select catalogue test…</option>
                  {filteredCatalogue.map((item) => <option key={item.id} value={item.id}>{item.test_code} — {item.test_name}{item.default_charge > 0 ? ` · GHS ${item.default_charge.toFixed(2)}` : ""}</option>)}
                </select>
                {canCreateCatalogue && catalogueSearch.trim() && filteredCatalogue.length === 0 && <button type="button" onClick={() => setCreateLabTestName(catalogueSearch.trim())} className="btn-secondary mt-2 w-full">Add {catalogueSearch.trim()}</button>}
              </div>
              <div>
                <label htmlFor="lab-test-name" className="mb-1 block text-xs font-semibold">Test name <span className="text-critical">*</span></label>
                <input id="lab-test-name" value={testName} onChange={(e) => setTestName(e.target.value)} className="input-medical w-full" placeholder="Test name" required />
              </div>
              <div>
                <label htmlFor="lab-category" className="mb-1 block text-xs font-semibold">Category</label>
                <input id="lab-category" value={category} onChange={(e) => setCategory(e.target.value)} className="input-medical w-full" placeholder="Category" />
              </div>
              <div>
                <label htmlFor="lab-priority" className="mb-1 block text-xs font-semibold">Priority</label>
                <select id="lab-priority" value={priority} onChange={(e) => setPriority(e.target.value)} className="input-medical w-full">
                  <option value="routine">Routine</option><option value="urgent">Urgent</option><option value="stat">STAT</option>
                </select>
              </div>
              <div>
                <label htmlFor="lab-amount" className="mb-1 block text-xs font-semibold">Charge (GHS) <span className="text-critical">*</span></label>
                <input id="lab-amount" value={amount} onChange={(e) => setAmount(e.target.value)} className="input-medical w-full" inputMode="decimal" min="0" step="0.01" type="number" placeholder="Charge (GHS)" required />
              </div>
              <div>
                <label htmlFor="lab-notes" className="mb-1 block text-xs font-semibold">Clinical notes</label>
                <textarea id="lab-notes" value={notes} onChange={(e) => setNotes(e.target.value)} className="input-medical w-full" rows={2} placeholder="Clinical notes" />
              </div>
              <div className="lg:col-span-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <p className="text-xs text-muted-foreground flex items-start gap-2"><LockKeyhole className="w-3.5 h-3.5 mt-0.5 shrink-0" aria-hidden="true" /> Chargeable tests remain blocked until Accounts releases them.</p>
                <button type="submit" disabled={creatingOrder} className="btn-primary inline-flex items-center justify-center gap-2 disabled:opacity-60"><Plus className="w-4 h-4" aria-hidden="true" /> Order test</button>
              </div>
            </form>
          </section>
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
            meta={`${orders.length} order${orders.length === 1 ? '' : 's'}`}
            filters={[
              { label: 'Order status', value: statusFilter, onChange: setStatusFilter, options: [{ value: 'all', label: 'All statuses' }, { value: 'ordered', label: 'Ordered' }, { value: 'sample_collected', label: 'Sample collected' }, { value: 'completed', label: 'Completed' }, { value: 'approved', label: 'Approved' }] },
              { label: 'Priority', value: priorityFilter, onChange: setPriorityFilter, options: [{ value: 'all', label: 'All priorities' }, { value: 'routine', label: 'Routine' }, { value: 'urgent', label: 'Urgent' }, { value: 'stat', label: 'STAT' }] },
              { label: 'Result state', value: resultFilter, onChange: setResultFilter, options: [{ value: 'all', label: 'All results' }, { value: 'with_result', label: 'Result entered' }, { value: 'awaiting_result', label: 'Awaiting result' }, { value: 'abnormal', label: 'Abnormal results' }] },
            ]}
            onSearch={() => setAppliedFilters({ status: statusFilter, priority: priorityFilter, result: resultFilter })}
            loading={loading}
            empty={false}
          >
            <thead>
              <tr>
                <th scope="col">Patient</th>
                <th scope="col">Laboratory test</th>
                <th scope="col">Priority</th>
                <th scope="col">Status</th>
                <th scope="col">Workflow progress</th>
                <th scope="col">Result</th>
                <th scope="col">Ordered</th>
                <th scope="col" className="text-right">Action</th>
              </tr>
            </thead>
            <tbody>
              {orders.filter((o) => {
                const result = resultsByOrder[o.id];
                const statusOk = appliedFilters.status === 'all' || o.status === appliedFilters.status;
                const priorityOk = appliedFilters.priority === 'all' || o.priority === appliedFilters.priority;
                const resultOk = appliedFilters.result === 'all'
                  || (appliedFilters.result === 'with_result' && !!result)
                  || (appliedFilters.result === 'awaiting_result' && !result)
                  || (appliedFilters.result === 'abnormal' && !!result?.is_abnormal);
                return statusOk && priorityOk && resultOk;
              }).map((o) => {
                const p = patients.find((x) => x.id === o.patient_id);
                const result = resultsByOrder[o.id];
                const item = catalogue.find((x) => x.id === o.lab_test_catalogue_id);
                const progress = o.status === 'approved' ? 100 : o.status === 'completed' ? 80 : o.status === 'sample_collected' ? 55 : 25;
                return (
                  <Fragment key={o.id}>
                    <tr id={`lab-order-${o.id}`} className={attentionOrderId === o.id ? 'bg-primary/5' : undefined}>
                      <td>
                        <div className="min-w-[170px]">
                          <p className="font-semibold">{p ? `${p.first_name} ${p.last_name}` : 'Patient record'}</p>
                          <p className="mt-0.5 text-xs text-muted-foreground">{p?.patient_code ?? o.patient_id.slice(0, 8)}</p>
                        </div>
                      </td>
                      <td>
                        <div className="min-w-[180px]">
                          <p className="font-medium">{o.test_name}</p>
                          <p className="mt-0.5 text-xs text-muted-foreground">{o.test_category ?? 'Uncategorised'}{item?.specimen_type ? ` · ${item.specimen_type}` : ''}</p>
                        </div>
                      </td>
                      <td>{o.priority === 'routine' ? <ClinicalStatusBadge status="started" label="Routine" /> : <ClinicalStatusBadge status={o.priority} label={o.priority.toUpperCase()} />}</td>
                      <td><ClinicalStatusBadge status={o.status} /></td>
                      <td><ClinicalProgressBar value={progress} label={progress === 100 ? 'Complete' : 'In workflow'} /></td>
                      <td>
                        {result ? (
                          <div className="max-w-[170px]">
                            <p className={`font-medium ${result.is_abnormal ? 'text-critical' : ''}`}>{result.numeric_value !== null ? `${result.numeric_value}${result.unit ? ` ${result.unit}` : ''}` : (result.result_data?.value ?? 'Result entered')}</p>
                            <p className="mt-0.5 text-xs text-muted-foreground">{result.is_abnormal ? 'Abnormal' : result.status.replace('_', ' ')}</p>
                          </div>
                        ) : <span className="text-xs text-muted-foreground">Awaiting result</span>}
                      </td>
                      <td className="whitespace-nowrap text-xs text-muted-foreground">{new Date(o.created_at).toLocaleString()}</td>
                      <td>
                        <div className="flex min-w-[220px] flex-wrap justify-end gap-2">
                          <ClinicalTableAction label={expandedOrderId === o.id ? 'Hide details' : 'View result'} onClick={() => setExpandedOrderId(expandedOrderId === o.id ? null : o.id)} />
                          {o.status === 'ordered' && <ClinicalTableAction label={orderAction === o.id ? 'Collecting…' : 'Collect sample'} onClick={() => void collectSample(o.id)} />}
                          {o.status === 'sample_collected' && <ClinicalTableAction label="Enter result" icon="acknowledge" onClick={() => { setExpandedOrderId(o.id); setResultFor(o.id); }} />}
                          {o.status === 'completed' && result && <ClinicalTableAction label={orderAction === o.id ? 'Approving…' : 'Approve'} icon="acknowledge" onClick={() => void approveResult(result.id, o.id, o.patient_id)} />}
                        </div>
                      </td>
                    </tr>
                    {expandedOrderId === o.id && (
                      <tr key={`${o.id}-details`} className="bg-muted/20">
                        <td colSpan={8}>
                          <div className="grid gap-4 lg:grid-cols-[1fr_1fr]">
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
                              {resultFor === o.id && o.status === 'sample_collected' ? (
                                <div className="mt-3 space-y-2">
                                  {item?.parameters && item.parameters.length > 0 && (
                                    <fieldset className="rounded-lg border border-border p-3 space-y-3">
                                      <legend className="px-1 text-xs font-semibold">Structured test parameters</legend>
                                      {item.parameters.filter((parameter) => parameter.code).map((parameter) => (
                                        <div key={parameter.code} className="grid gap-1 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] sm:items-center">
                                          <label htmlFor={`lab-param-${o.id}-${parameter.code}`} className="text-sm">
                                            {parameter.label ?? parameter.name ?? parameter.code}{parameter.required ? ' *' : ''}
                                            {(parameter.unit || parameter.reference_text || parameter.reference_low != null || parameter.reference_high != null) && (
                                              <span className="mt-0.5 block text-xs text-muted-foreground">
                                                {[parameter.unit, parameter.reference_text, parameter.reference_low != null || parameter.reference_high != null ? `Reference ${parameter.reference_low ?? '—'}–${parameter.reference_high ?? '—'}` : ''].filter(Boolean).join(' · ')}
                                              </span>
                                            )}
                                          </label>
                                          <input id={`lab-param-${o.id}-${parameter.code}`} value={parameterValues[parameter.code] ?? ''} onChange={(e) => setParameterValues((current) => ({ ...current, [parameter.code]: e.target.value }))} className="input-medical w-full" inputMode={parameter.type === 'numeric' || parameter.type === 'number' ? 'decimal' : 'text'} aria-required={Boolean(parameter.required)} placeholder={`Enter ${parameter.label ?? parameter.name ?? parameter.code}`} />
                                        </div>
                                      ))}
                                    </fieldset>
                                  )}
                                  <div className="grid gap-2 sm:grid-cols-2">
                                    <input value={numericValue} onChange={(e) => setNumericValue(e.target.value)} className="input-medical w-full" inputMode="decimal" placeholder={item?.unit ? `Single numeric result (${item.unit})` : 'Single numeric result (optional for structured tests)'} aria-label="Numeric result" />
                                    {item?.unit && <div className="input-medical bg-muted/30 text-sm flex items-center">Unit: {item.unit}</div>}
                                  </div>
                                  <textarea value={resultText} onChange={(e) => setResultText(e.target.value)} className="input-medical w-full" rows={2} placeholder="Result values / narrative" aria-label="Result values or narrative" />
                                  <input value={interpretation} onChange={(e) => setInterpretation(e.target.value)} className="input-medical w-full" placeholder="Interpretation" aria-label="Result interpretation" />
                                  <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={isAbnormal} onChange={(e) => setIsAbnormal(e.target.checked)} /> Abnormal result</label>
                                  <div className="flex gap-2"><button type="button" disabled={savingResultFor === o.id} onClick={() => void submitResult(o.id)} className="btn-primary text-xs disabled:opacity-60">{savingResultFor === o.id ? 'Saving…' : 'Submit result'}</button><button type="button" disabled={savingResultFor === o.id} onClick={() => { setResultFor(null); setParameterValues({}); }} className="btn-ghost text-xs disabled:opacity-60">Cancel</button></div>
                                </div>
                              ) : (
                                <div className="mt-3 flex flex-wrap gap-2">
                                  {o.status === 'ordered' && <button type="button" onClick={() => void collectSample(o.id)} className="btn-secondary text-xs">Collect sample</button>}
                                  {o.status === 'sample_collected' && <button type="button" onClick={() => setResultFor(o.id)} className="btn-primary text-xs">Enter result</button>}
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
      </OperationalWorklistShell>
      {createLabTestName && <CatalogueCreateModal kind="lab" initialName={createLabTestName} userRoles={user?.roles ?? []} userPermissions={user?.permissions ?? []} userDepartment={user?.department} onCreated={(created) => { setCatalogueSearch(created?.test_name ?? createLabTestName); void loadAll(); }} onClose={() => setCreateLabTestName('')} />}
    </>
  );
}
