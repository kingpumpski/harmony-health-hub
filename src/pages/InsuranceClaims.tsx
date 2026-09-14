import { useCallback, useEffect, useState } from 'react';
import { Plus, RefreshCw, Save, ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

type Claim = {
  id: string;
  patient_id: string;
  payer_name: string;
  member_number: string | null;
  claim_number: string | null;
  amount_claimed: number;
  amount_approved: number | null;
  amount_paid: number;
  status: string;
  rejection_reason: string | null;
  service_from: string | null;
  service_to: string | null;
  created_at: string;
};

type Patient = {
  id: string;
  patient_code: string;
  first_name: string;
  last_name: string;
};

type Invoice = {
  id: string;
  invoice_number: string;
  patient_id: string;
  total_amount: number;
  paid_amount: number;
  outstanding_amount: number;
  status: string;
  created_at: string;
};

type DraftForm = {
  patientId: string;
  invoiceId: string;
  payerName: string;
  memberNumber: string;
  amountClaimed: string;
};

type FinancialEdit = {
  approved: string;
  paid: string;
  number: string;
  rejection: string;
};

const statuses = [
  'draft',
  'submitted',
  'acknowledged',
  'under_review',
  'approved',
  'partially_approved',
  'rejected',
  'paid',
  'resubmission_required',
  'voided',
];

const emptyDraft: DraftForm = {
  patientId: '',
  invoiceId: '',
  payerName: '',
  memberNumber: '',
  amountClaimed: '',
};

export default function InsuranceClaims() {
  const { toast } = useToast();
  const [claims, setClaims] = useState<Claim[]>([]);
  const [patients, setPatients] = useState<Patient[]>([]);
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [busy, setBusy] = useState(false);
  const [filter, setFilter] = useState('all');
  const [showCreate, setShowCreate] = useState(false);
  const [draft, setDraft] = useState<DraftForm>(emptyDraft);
  const [edit, setEdit] = useState<Record<string, FinancialEdit>>({});

  const load = useCallback(async () => {
    const [{ data: patientData, error: patientError }, { data: claimData, error: claimError }] = await Promise.all([
      supabase
        .from('patients')
        .select('id,patient_code,first_name,last_name')
        .order('created_at', { ascending: false })
        .limit(500),
      supabase
        .from('insurance_claims')
        .select('id,patient_id,payer_name,member_number,claim_number,amount_claimed,amount_approved,amount_paid,status,rejection_reason,service_from,service_to,created_at')
        .order('created_at', { ascending: false })
        .limit(100),
    ]);

    if (patientError || claimError) {
      toast({
        title: 'Unable to load claims',
        description: (patientError || claimError)?.message,
        variant: 'destructive',
      });
    }

    setPatients((patientData ?? []) as Patient[]);
    setClaims((claimData ?? []) as Claim[]);
  }, [toast]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const patientId = draft.patientId;
    if (!patientId) {
      setInvoices([]);
      return;
    }

    let active = true;
    const loadInvoices = async () => {
      const { data, error } = await supabase
        .from('invoices')
        .select('id,invoice_number,patient_id,total_amount,paid_amount,outstanding_amount,status,created_at')
        .eq('patient_id', patientId)
        .neq('status', 'cancelled')
        .gt('total_amount', 0)
        .order('created_at', { ascending: false })
        .limit(50);

      if (!active) return;
      if (error) {
        setInvoices([]);
        toast({ title: 'Unable to load patient invoices', description: error.message, variant: 'destructive' });
        return;
      }

      setInvoices((data ?? []) as Invoice[]);
    };

    void loadInvoices();
    return () => {
      active = false;
    };
  }, [draft.patientId, toast]);

  const patient = (id: string) => {
    const match = patients.find((item) => item.id === id);
    return match ? `${match.patient_code} — ${match.first_name} ${match.last_name}` : 'Patient';
  };

  const createDraft = async () => {
    const amount = Number(draft.amountClaimed);
    if (!draft.patientId || !draft.invoiceId || !draft.payerName.trim()) {
      toast({ title: 'Patient, invoice and payer are required', variant: 'destructive' });
      return;
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      toast({ title: 'Enter a valid claim amount greater than zero', variant: 'destructive' });
      return;
    }

    setBusy(true);
    const { error } = await supabase.rpc(
      'create_insurance_claim_draft',
      {
        _patient_id: draft.patientId,
        _payer_name: draft.payerName.trim(),
        _member_number: draft.memberNumber.trim() || null,
        _amount_claimed: amount,
        _invoice_id: draft.invoiceId,
      } as never,
    );
    setBusy(false);

    if (error) {
      toast({ title: 'Claim draft creation failed', description: error.message, variant: 'destructive' });
      return;
    }

    toast({ title: 'Claim draft created' });
    setDraft(emptyDraft);
    setInvoices([]);
    setShowCreate(false);
    await load();
  };

  const begin = (claim: Claim) => {
    setEdit((current) => ({
      ...current,
      [claim.id]: {
        approved: claim.amount_approved == null ? '' : String(claim.amount_approved),
        paid: String(claim.amount_paid || 0),
        number: claim.claim_number || '',
        rejection: claim.rejection_reason || '',
      },
    }));
  };

  const transition = async (id: string, status: string) => {
    setBusy(true);
    const { error } = await supabase.rpc(
      'transition_insurance_claim',
      {
        _claim_id: id,
        _to_status: status,
        _notes: status === 'rejected' ? 'Claim rejected during review' : 'Status updated from claims queue',
      } as never,
    );
    setBusy(false);

    if (error) {
      toast({ title: 'Claim transition failed', description: error.message, variant: 'destructive' });
    } else {
      toast({ title: 'Claim status updated' });
      await load();
    }
  };

  const saveFinancials = async (claim: Claim) => {
    const value = edit[claim.id] || {
      approved: '',
      paid: String(claim.amount_paid || 0),
      number: claim.claim_number || '',
      rejection: claim.rejection_reason || '',
    };
    const approved = value.approved === '' ? null : Number(value.approved);
    const paid = value.paid === '' ? null : Number(value.paid);

    if ((approved !== null && (!Number.isFinite(approved) || approved < 0)) || (paid !== null && (!Number.isFinite(paid) || paid < 0))) {
      toast({ title: 'Financial amounts must be valid and non-negative', variant: 'destructive' });
      return;
    }

    setBusy(true);
    const { error } = await supabase.rpc(
      'update_insurance_claim_financials',
      {
        _claim_id: claim.id,
        _amount_approved: approved,
        _amount_paid: paid,
        _claim_number: value.number.trim() || null,
        _rejection_reason: value.rejection.trim() || null,
      } as never,
    );
    setBusy(false);

    if (error) {
      toast({ title: 'Financial update failed', description: error.message, variant: 'destructive' });
      return;
    }

    toast({ title: 'Claim financials saved' });
    setEdit((current) => {
      const next = { ...current };
      delete next[claim.id];
      return next;
    });
    await load();
  };

  const visible = filter === 'all' ? claims : claims.filter((claim) => claim.status === filter);

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-heading font-bold">Insurance Claims</h1>
          <p className="text-sm text-muted-foreground">Financial claim lifecycle, adjudication, rejection and resubmission control.</p>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowCreate((value) => !value)} className="inline-flex items-center gap-2 rounded-md bg-primary px-3 py-2 text-sm text-primary-foreground">
            <Plus className="h-4 w-4" />
            New claim draft
          </button>
          <button onClick={() => void load()} className="rounded-md border p-2" aria-label="Refresh" disabled={busy}>
            <RefreshCw className="h-4 w-4" />
          </button>
        </div>
      </header>

      {showCreate && (
        <section className="rounded-xl border bg-card p-4 space-y-4">
          <div className="flex items-center gap-2">
            <ShieldCheck className="h-5 w-5" />
            <div>
              <h2 className="font-semibold">Create claim draft</h2>
              <p className="text-xs text-muted-foreground">Select the exact patient invoice that supports this claim before creating the draft.</p>
            </div>
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5">
            <select value={draft.patientId} onChange={(event) => setDraft((current) => ({ ...current, patientId: event.target.value, invoiceId: '' }))} className="rounded-md border bg-background p-2">
              <option value="">Select patient</option>
              {patients.map((item) => <option key={item.id} value={item.id}>{item.patient_code} — {item.first_name} {item.last_name}</option>)}
            </select>
            <select disabled={!draft.patientId || invoices.length === 0} value={draft.invoiceId} onChange={(event) => setDraft((current) => ({ ...current, invoiceId: event.target.value }))} className="rounded-md border bg-background p-2">
              <option value="">{!draft.patientId ? 'Select patient first' : invoices.length === 0 ? 'No eligible invoices' : 'Select invoice'}</option>
              {invoices.map((invoice) => <option key={invoice.id} value={invoice.id}>{invoice.invoice_number} — {Number(invoice.total_amount || 0).toLocaleString()} — {invoice.status}</option>)}
            </select>
            <input placeholder="Payer / insurer" value={draft.payerName} onChange={(event) => setDraft((current) => ({ ...current, payerName: event.target.value }))} className="rounded-md border bg-background p-2" />
            <input placeholder="Member number" value={draft.memberNumber} onChange={(event) => setDraft((current) => ({ ...current, memberNumber: event.target.value }))} className="rounded-md border bg-background p-2" />
            <input type="number" min="0.01" step="0.01" placeholder="Amount claimed" value={draft.amountClaimed} onChange={(event) => setDraft((current) => ({ ...current, amountClaimed: event.target.value }))} className="rounded-md border bg-background p-2" />
          </div>
          <button disabled={busy || !draft.invoiceId} onClick={() => void createDraft()} className="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground disabled:opacity-50">{busy ? 'Creating…' : 'Create draft'}</button>
        </section>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <ShieldCheck className="h-5 w-5" />
        <select value={filter} onChange={(event) => setFilter(event.target.value)} className="rounded-md border bg-background p-2">
          <option value="all">All statuses</option>
          {statuses.map((status) => <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>)}
        </select>
        <span className="text-sm text-muted-foreground">{visible.length} claim{visible.length === 1 ? '' : 's'}</span>
      </div>

      <div className="grid gap-3">
        {visible.map((claim) => {
          const value = edit[claim.id];
          const locked = claim.status === 'paid' || claim.status === 'voided';
          return (
            <article key={claim.id} className="rounded-xl border bg-card p-4">
              <div className="flex flex-wrap justify-between gap-3">
                <div>
                  <h2 className="font-semibold">{claim.claim_number || 'Claim number not recorded'}</h2>
                  <p className="text-sm">{patient(claim.patient_id)} · {claim.payer_name}</p>
                  <p className="text-xs text-muted-foreground">{claim.status.replaceAll('_', ' ')} · claimed {Number(claim.amount_claimed || 0).toLocaleString()}</p>
                </div>
                <select disabled={busy || locked} value="" onChange={(event) => { if (event.target.value) void transition(claim.id, event.target.value); }} className="rounded-md border bg-background px-2 py-1 text-sm">
                  <option value="">Change status…</option>
                  {statuses.filter((status) => status !== claim.status).map((status) => <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>)}
                </select>
              </div>
              <div className="mt-3 grid grid-cols-1 gap-2 text-xs sm:grid-cols-2 lg:grid-cols-4">
                <div>Approved: {Number(claim.amount_approved || 0).toLocaleString()}</div>
                <div>Paid: {Number(claim.amount_paid || 0).toLocaleString()}</div>
                <div>Member: {claim.member_number || 'Not recorded'}</div>
                <div>Service: {claim.service_from ? new Date(claim.service_from).toLocaleDateString() : '—'}{claim.service_to ? ` → ${new Date(claim.service_to).toLocaleDateString()}` : ''}</div>
              </div>
              {claim.rejection_reason && <p className="mt-2 text-xs text-destructive">Rejection: {claim.rejection_reason}</p>}
              {!locked && (value ? (
                <div className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-4">
                  <input type="number" min="0" step="0.01" placeholder="Approved amount" value={value.approved} onChange={(event) => setEdit((current) => ({ ...current, [claim.id]: { ...value, approved: event.target.value } }))} className="rounded-md border bg-background p-2 text-sm" />
                  <input type="number" min="0" step="0.01" placeholder="Paid amount" value={value.paid} onChange={(event) => setEdit((current) => ({ ...current, [claim.id]: { ...value, paid: event.target.value } }))} className="rounded-md border bg-background p-2 text-sm" />
                  <input placeholder="Claim number" value={value.number} onChange={(event) => setEdit((current) => ({ ...current, [claim.id]: { ...value, number: event.target.value } }))} className="rounded-md border bg-background p-2 text-sm" />
                  <input placeholder="Rejection reason" value={value.rejection} onChange={(event) => setEdit((current) => ({ ...current, [claim.id]: { ...value, rejection: event.target.value } }))} className="rounded-md border bg-background p-2 text-sm" />
                  <button disabled={busy} onClick={() => void saveFinancials(claim)} className="inline-flex items-center justify-center gap-1 rounded-md bg-primary px-3 py-2 text-sm text-primary-foreground sm:col-span-2 lg:col-span-1"><Save className="h-4 w-4" />Save financials</button>
                </div>
              ) : <button onClick={() => begin(claim)} className="mt-4 rounded-md border px-3 py-2 text-sm">Edit financials</button>)}
            </article>
          );
        })}
        {visible.length === 0 && <p className="text-sm text-muted-foreground">No claims match the selected status.</p>}
      </div>
    </div>
  );
}
