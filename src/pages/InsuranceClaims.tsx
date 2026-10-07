// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import RefreshButton from '@/components/ui/RefreshButton';
import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus, RefreshCw, Save, ShieldCheck, Activity, Clock3, CheckCircle2, AlertTriangle, Link2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useToast } from '@/hooks/use-toast';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';

type Claim = { id: string; patient_id: string; payer_name: string; member_number: string | null; claim_number: string | null; amount_claimed: number; amount_approved: number | null; amount_paid: number; status: string; rejection_reason: string | null; service_from: string | null; service_to: string | null; created_at: string };
type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
type ReconciliationContext = { claim_id: string; invoice_id: string | null; insurance_company_id: string | null; insurer_code: string | null; insurer_name: string | null; invoice_insurance_total: number };
type DraftForm = { patientId: string; payerName: string; memberNumber: string; amountClaimed: string };
type FinancialEdit = { approved: string; paid: string; number: string; rejection: string };
const statuses = ['draft','submitted','acknowledged','under_review','approved','partially_approved','rejected','paid','resubmission_required','voided'];
const emptyDraft: DraftForm = { patientId: '', payerName: '', memberNumber: '', amountClaimed: '' };

export default function InsuranceClaims() {
  const { toast } = useToast();
  const [claims, setClaims] = useState<Claim[]>([]); const [patients, setPatients] = useState<Patient[]>([]);
  const [reconciliation, setReconciliation] = useState<Record<string, ReconciliationContext>>({});
  const [busy, setBusy] = useState(false); const [reconciling, setReconciling] = useState<Record<string, boolean>>({});
  const [filter, setFilter] = useState('all'); const [payerFilter, setPayerFilter] = useState<'all' | 'nhis' | 'other'>('all'); const [showCreate, setShowCreate] = useState(false);
  const [draft, setDraft] = useState<DraftForm>(emptyDraft); const [edit, setEdit] = useState<Record<string, FinancialEdit>>({});

  const load = useCallback(async () => {
    const [workspace, patientData] = await Promise.all([getOperationalWorkspace('insurance', 100), searchPatientDirectory('', 500)]);
    const patientError = patientData.error; const claimError = workspace.error;
    const claimData = { data: (workspace.data as any)?.claims ?? [] };
    const loadedClaims = (claimData.data ?? []) as Claim[];
    if (patientError || claimError) toast({ title: 'Unable to load claims', description: (patientError || claimError)?.message, variant: 'destructive' });
    setPatients((patientData.data ?? []) as Patient[]); setClaims(loadedClaims);

    if (loadedClaims.length) {
      const { data, error } = await supabase.rpc('get_insurance_claim_reconciliation_context', { _claim_ids: loadedClaims.map((claim) => claim.id) } as never);
      if (error) {
        toast({ title: 'Reconciliation context unavailable', description: error.message, variant: 'destructive' });
      } else {
        const next = Object.fromEntries(((data ?? []) as ReconciliationContext[]).map((item) => [item.claim_id, item]));
        setReconciliation(next);
      }
    } else setReconciliation({});
  }, [toast]);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => { const channel = supabase.channel('insurance-claims-live').on('broadcast', { event: 'refresh' }, () => void load()).subscribe(); return () => { void supabase.removeChannel(channel); }; }, [load]);

  const patient = (id: string) => { const match = patients.find((item) => item.id === id); return match ? `${match.patient_code} — ${match.first_name} ${match.last_name}` : 'Patient'; };
  const counts = useMemo(() => ({ open: claims.filter((c) => !['paid','voided'].includes(c.status)).length, review: claims.filter((c) => ['submitted','acknowledged','under_review'].includes(c.status)).length, approved: claims.filter((c) => ['approved','partially_approved'].includes(c.status)).length, exceptions: claims.filter((c) => ['rejected','resubmission_required'].includes(c.status)).length, paid: claims.filter((c) => c.status === 'paid').length }), [claims]);

  const createDraft = async () => {
    const amount = Number(draft.amountClaimed);
    if (!draft.patientId || !draft.payerName.trim()) return void toast({ title: 'Patient and payer are required', variant: 'destructive' });
    if (!Number.isFinite(amount) || amount < 0) return void toast({ title: 'Enter a valid non-negative claim amount', variant: 'destructive' });
    setBusy(true); const { error } = await supabase.rpc('create_insurance_claim_draft', { _patient_id: draft.patientId, _payer_name: draft.payerName.trim(), _member_number: draft.memberNumber.trim() || null, _amount_claimed: amount, _invoice_id: null } as never); setBusy(false);
    if (error) return void toast({ title: 'Claim draft creation failed', description: error.message, variant: 'destructive' });
    playWorkflowSound('success'); toast({ title: 'Claim draft created' }); setDraft(emptyDraft); setShowCreate(false); await load();
  };

  const reconcile = async (claim: Claim) => {
    const context = reconciliation[claim.id];
    if (!context?.invoice_id) return void toast({ title: 'No invoice is linked to this claim', description: 'Reconciliation requires the claim to reference an invoice.', variant: 'destructive' });
    setReconciling((current) => ({ ...current, [claim.id]: true }));
    const { error } = await supabase.rpc('reconcile_insurance_claim_to_invoice', { _claim_id: claim.id } as never);
    setReconciling((current) => { const next = { ...current }; delete next[claim.id]; return next; });
    if (error) return void toast({ title: 'Claim reconciliation failed', description: error.message, variant: 'destructive' });
    playWorkflowSound('success'); toast({ title: 'Claim reconciled', description: 'Canonical insurer and invoice insurance coverage were applied.' }); await load();
  };

  const begin = (claim: Claim) => setEdit((current) => ({ ...current, [claim.id]: { approved: claim.amount_approved == null ? '' : String(claim.amount_approved), paid: String(claim.amount_paid || 0), number: claim.claim_number || '', rejection: claim.rejection_reason || '' } }));
  const transition = async (id: string, status: string) => { setBusy(true); const { error } = await supabase.rpc('transition_insurance_claim_canonical', { _claim_id: id, _status: status, _amount_approved: null, _amount_paid: null, _rejection_reason: status === 'rejected' ? 'Claim rejected during review' : null, _notes: status === 'rejected' ? 'Claim rejected during review' : 'Status updated from claims queue' } as never); setBusy(false); if (error) return void toast({ title: 'Claim transition failed', description: error.message, variant: 'destructive' }); playWorkflowSound(status === 'rejected' || status === 'resubmission_required' ? 'warning' : 'success'); toast({ title: 'Claim status updated' }); await load(); };
  const saveFinancials = async (claim: Claim) => { const value = edit[claim.id] || { approved: '', paid: String(claim.amount_paid || 0), number: claim.claim_number || '', rejection: claim.rejection_reason || '' }; const approved = value.approved === '' ? null : Number(value.approved); const paid = value.paid === '' ? null : Number(value.paid); if ((approved !== null && (!Number.isFinite(approved) || approved < 0)) || (paid !== null && (!Number.isFinite(paid) || paid < 0))) return void toast({ title: 'Financial amounts must be valid and non-negative', variant: 'destructive' }); setBusy(true); const { error } = await supabase.rpc('update_insurance_claim_financials', { _claim_id: claim.id, _amount_approved: approved, _amount_paid: paid, _claim_number: value.number.trim() || null, _rejection_reason: value.rejection.trim() || null } as never); setBusy(false); if (error) return void toast({ title: 'Financial update failed', description: error.message, variant: 'destructive' }); playWorkflowSound('success'); toast({ title: 'Claim financials saved' }); setEdit((current) => { const next = { ...current }; delete next[claim.id]; return next; }); await load(); };

  const visible = claims.filter((claim) => (filter === 'all' || claim.status === filter) && (payerFilter === 'all' || (payerFilter === 'nhis' ? /nhis|national health insurance/i.test(`${claim.payer_name} ${reconciliation[claim.id]?.insurer_name ?? ''}`) : !/nhis|national health insurance/i.test(`${claim.payer_name} ${reconciliation[claim.id]?.insurer_name ?? ''}`))));
  const cards = [{ label: 'Open claims', value: counts.open, icon: Activity, tone: 'text-info', surface: 'bg-info/5', status: 'all' }, { label: 'Awaiting payer review', value: counts.review, icon: Clock3, tone: 'text-warning', surface: 'bg-warning/5', status: 'under_review' }, { label: 'Approved / partial', value: counts.approved, icon: CheckCircle2, tone: 'text-success', surface: 'bg-success/5', status: 'approved' }, { label: 'Exceptions', value: counts.exceptions, icon: AlertTriangle, tone: 'text-destructive', surface: 'bg-destructive/5', status: 'rejected' }];

  return (
    <OperationalWorklistShell
      icon={ShieldCheck}
      eyebrow="Business · Insurance"
      title="Insurance Claims"
      description="Live financial claim lifecycle, adjudication, rejection and resubmission control."
      actions={<><button type="button" onClick={() => setShowCreate((value) => !value)} className="btn-primary inline-flex items-center gap-2"><Plus className="h-4 w-4" />{showCreate ? "Close draft form" : "New claim draft"}</button><RefreshButton onClick={() => void load()} loading={busy} /></>}
      counters={cards.map(({ label, value, tone, surface }) => ({ label, value, tone, surface }))}
      beforeList={showCreate ? <section className="card-medical p-5 sm:p-6 space-y-4" aria-labelledby="claim-draft-heading"><div><h2 id="claim-draft-heading" className="font-semibold">Create claim draft</h2><p className="text-xs text-muted-foreground">Creates the draft through the server-authoritative claims workflow.</p></div><div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4"><label className="space-y-1.5 text-sm"><span className="font-medium">Patient</span><select required value={draft.patientId} onChange={(event) => setDraft((current) => ({ ...current, patientId: event.target.value }))} className="input-medical w-full"><option value="">Select patient</option>{patients.map((item) => <option key={item.id} value={item.id}>{item.patient_code} — {item.first_name} {item.last_name}</option>)}</select></label><label className="space-y-1.5 text-sm"><span className="font-medium">Payer / insurer</span><input required placeholder="Payer / insurer" value={draft.payerName} onChange={(event) => setDraft((current) => ({ ...current, payerName: event.target.value }))} className="input-medical w-full" /></label><label className="space-y-1.5 text-sm"><span className="font-medium">Member number</span><input placeholder="Member number" value={draft.memberNumber} onChange={(event) => setDraft((current) => ({ ...current, memberNumber: event.target.value }))} className="input-medical w-full" /></label><label className="space-y-1.5 text-sm"><span className="font-medium">Amount claimed</span><input required type="number" min="0" step="0.01" placeholder="Amount claimed" value={draft.amountClaimed} onChange={(event) => setDraft((current) => ({ ...current, amountClaimed: event.target.value }))} className="input-medical w-full" /></label></div><button type="button" disabled={busy} onClick={() => void createDraft()} className="btn-primary disabled:opacity-50">{busy ? "Creating…" : "Create draft"}</button></section> : null}
      listTitle="Claims worklist"
      listDescription="Filter by NHIS versus other insurers and by claim lifecycle status. Amounts are displayed in the facility billing currency (GHS)."
      listMeta={<div className="flex flex-wrap items-center gap-2"><select aria-label="Filter NHIS claims" value={payerFilter} onChange={(event) => setPayerFilter(event.target.value as "all" | "nhis" | "other")} className="input-medical h-9 py-1"><option value="all">All payers</option><option value="nhis">NHIS claims</option><option value="other">Other insurers</option></select><select aria-label="Filter claims by status" value={filter} onChange={(event) => setFilter(event.target.value)} className="input-medical h-9 py-1"><option value="all">All statuses</option>{statuses.map((status) => <option key={status} value={status}>{status.replaceAll("_", " ")}</option>)}</select><span>{visible.length} claim{visible.length === 1 ? "" : "s"} · {counts.paid} paid</span></div>}
      empty={!visible.length}
      emptyTitle="No claims match the selected status"
      emptyDescription="Change the payer or status filter, or create a new claim draft."
    >
      {visible.map((claim) => {
        const value = edit[claim.id]; const context = reconciliation[claim.id]; const locked = claim.status === "paid" || claim.status === "voided"; const reconcilingNow = Boolean(reconciling[claim.id]);
        return (
          <article key={claim.id} className="px-5 py-4 transition-colors hover:bg-muted/30">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
              <div className="min-w-0">
                <p className="font-medium">{claim.claim_number || "Claim number not recorded"}</p>
                <p className="mt-1 text-sm">{patient(claim.patient_id)} · {context?.insurer_name || claim.payer_name}</p>
                <div className="mt-2 flex flex-wrap gap-2 text-xs text-muted-foreground"><span className="rounded-full bg-primary/10 px-2 py-1 text-primary capitalize">{claim.status.replaceAll("_"," ")}</span><span className="rounded-full bg-muted px-2 py-1">{/nhis|national health insurance/i.test(`${claim.payer_name} ${context?.insurer_name ?? ""}`) ? "NHIS" : "Insurance"}</span><span>Currency GHS</span><span>Claimed {Number(claim.amount_claimed || 0).toLocaleString()}</span><span>Approved {Number(claim.amount_approved || 0).toLocaleString()}</span><span>Paid {Number(claim.amount_paid || 0).toLocaleString()}</span></div>
                <div className="mt-3 grid grid-cols-1 gap-2 text-xs text-muted-foreground sm:grid-cols-2 lg:grid-cols-4"><div>Member: {claim.member_number || "Not recorded"}</div><div>Canonical insurer: {context?.insurer_name ? `${context.insurer_name}${context.insurer_code ? ` · ${context.insurer_code}` : ''}` : "Not linked"}</div><div>Invoice insurance: {context?.invoice_id ? Number(context.invoice_insurance_total || 0).toLocaleString() : "No invoice"}</div><div className="sm:col-span-2 lg:col-span-1">Rejection: {claim.rejection_reason || "None recorded"}</div></div>
              </div>
              <div className="flex flex-col gap-2 lg:w-52">
                <select aria-label={`Change status for ${claim.claim_number || "claim"}`} disabled={busy || locked} value="" onChange={(event) => { if (event.target.value) void transition(claim.id, event.target.value); }} className="input-medical w-full text-sm"><option value="">Change status…</option>{statuses.filter((status) => status !== claim.status).map((status) => <option key={status} value={status}>{status.replaceAll("_", " ")}</option>)}</select>
                {!locked && context?.invoice_id ? <button type="button" disabled={busy || reconcilingNow} onClick={() => void reconcile(claim)} className="btn-secondary inline-flex items-center justify-center gap-2 text-sm"><Link2 className="h-4 w-4" />{reconcilingNow ? "Reconciling…" : "Reconcile invoice"}</button> : null}
              </div>
            </div>
            {!locked && (value ? <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5"><input type="number" min="0" step="0.01" aria-label="Approved amount" placeholder="Approved amount" value={value.approved} onChange={(event) => setEdit((current) => ({ ...current, [claim.id]: { ...value, approved: event.target.value } }))} className="input-medical text-sm" /><input type="number" min="0" step="0.01" aria-label="Paid amount" placeholder="Paid amount" value={value.paid} onChange={(event) => setEdit((current) => ({ ...current, [claim.id]: { ...value, paid: event.target.value } }))} className="input-medical text-sm" /><input aria-label="Claim number" placeholder="Claim number" value={value.number} onChange={(event) => setEdit((current) => ({ ...current, [claim.id]: { ...value, number: event.target.value } }))} className="input-medical text-sm" /><input aria-label="Rejection reason" placeholder="Rejection reason" value={value.rejection} onChange={(event) => setEdit((current) => ({ ...current, [claim.id]: { ...value, rejection: event.target.value } }))} className="input-medical text-sm" /><button type="button" disabled={busy} onClick={() => void saveFinancials(claim)} className="btn-primary inline-flex items-center justify-center gap-1 text-sm"><Save className="h-4 w-4" />Save financials</button></div> : <button type="button" onClick={() => begin(claim)} className="btn-secondary mt-4 text-sm">Edit financials</button>)}
          </article>
        );
      })}
    </OperationalWorklistShell>
  );
}
