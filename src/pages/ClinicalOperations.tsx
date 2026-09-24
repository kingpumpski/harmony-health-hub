import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { useCallback, useEffect, useState, type ElementType } from 'react';
import { Link } from 'react-router-dom';
import { Activity, BedDouble, ClipboardList, Droplets, RefreshCw, ShieldCheck, Siren, Stethoscope } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { searchPatientDirectory } from '@/lib/patientDirectory';
import { notifyMasterDataChanged } from '@/lib/masterDataEvents';

type Tab = 'capacity' | 'nursing' | 'emergency' | 'theatre' | 'transfusion' | 'insurance';
type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
type Row = Record<string, unknown>;
const tabs: [Tab, string, ElementType][] = [
  ['capacity', 'Ward & Beds', BedDouble], ['nursing', 'Nursing', ClipboardList], ['emergency', 'Emergency', Siren],
  ['theatre', 'Theatre', Stethoscope], ['transfusion', 'Transfusion', Droplets], ['insurance', 'Insurance', ShieldCheck],
];
const transitions: Record<Exclude<Tab, 'capacity' | 'nursing'>, string[]> = {
  emergency: ['waiting', 'triage', 'treatment', 'observation', 'admitted', 'discharged', 'referred', 'left_without_being_seen', 'cancelled'],
  theatre: ['requested', 'approved', 'scheduled', 'in_progress', 'completed', 'postponed', 'cancelled'],
  transfusion: ['issued', 'running', 'completed', 'stopped', 'cancelled'],
  insurance: ['draft', 'submitted', 'acknowledged', 'under_review', 'approved', 'partially_approved', 'rejected', 'paid', 'resubmission_required', 'voided'],
};
const roleModules: Record<string, Tab[]> = {
  admin: ['capacity', 'nursing', 'emergency', 'theatre', 'transfusion', 'insurance'],
  practitioner: ['capacity', 'nursing', 'emergency', 'theatre', 'transfusion'],
  nurse: ['capacity', 'nursing', 'emergency', 'theatre', 'transfusion'],
  midwife: ['capacity', 'nursing', 'emergency', 'transfusion'],
  specialist_nurse: ['capacity', 'nursing', 'emergency', 'theatre', 'transfusion'],
  accountant: ['insurance'],
};

export default function ClinicalOperations() {
  const { user } = useAuth();
  const allowedTabs = roleModules[String(user?.role ?? '')] ?? [];
  const [tab, setTab] = useState<Tab>(allowedTabs[0] ?? 'capacity');
  const [patients, setPatients] = useState<Patient[]>([]);
  const [rows, setRows] = useState<Row[]>([]);
  const [patientId, setPatientId] = useState('');
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState<Record<string, string>>({});
  const set = (key: string, value: string) => setForm((current) => ({ ...current, [key]: value }));
  const workspaceModule = tab === 'capacity' ? 'ward' : tab === 'nursing' ? 'nursing_care' : tab;

  useEffect(() => {
    if (allowedTabs.length > 0 && !allowedTabs.includes(tab)) setTab(allowedTabs[0]);
  }, [allowedTabs, tab]);

  const load = useCallback(async () => {
    if (!allowedTabs.includes(tab)) return;
    const workspaceResult = await getOperationalWorkspace(workspaceModule, 50);
    if (workspaceResult.error) {
      setRows([]);
      toast({ title: 'Unable to load records', description: workspaceResult.error.message, variant: 'destructive' });
    } else {
      const payload = (workspaceResult.data ?? {}) as Record<string, unknown>;
      const rowData = tab === 'capacity' ? payload.wards ?? [] : tab === 'nursing' ? payload.care_plans ?? [] : tab === 'theatre' ? payload.cases ?? [] : tab === 'transfusion' ? payload.records ?? [] : tab === 'insurance' ? payload.claims ?? [] : payload.cases ?? [];
      setRows(rowData as Row[]);
    }
    if (tab !== 'capacity') {
      const patientResult = await searchPatientDirectory('', 300);
      if (patientResult.error) toast({ title: 'Unable to load patient directory', description: patientResult.error.message, variant: 'destructive' });
      else setPatients((patientResult.data ?? []) as Patient[]);
    }
  }, [allowedTabs, tab, workspaceModule]);

  useEffect(() => { void load(); }, [load]);

  const save = async () => {
    if (!user || busy) return;
    setBusy(true);
    try {
      let error: null | { message: string } = null;
      if (tab === 'capacity') {
        const result = await supabase.rpc('create_ward_unit', { _name: form.name, _code: form.code, _specialty: form.specialty || null, _gender_policy: form.gender_policy || 'mixed' } as never);
        error = result.error;
      } else {
        if (!patientId) throw new Error('Select a patient first.');
        if (tab === 'nursing') {
          const result = await supabase.rpc('create_nursing_care_plan', { _patient_id: patientId, _problem: form.problem, _goal: form.goal, _interventions: form.interventions, _priority: form.priority || 'routine' } as never); error = result.error;
        } else if (tab === 'emergency') {
          const result = await supabase.rpc('create_emergency_case', { _patient_id: patientId, _chief_complaint: form.complaint, _acuity: form.acuity || 'urgent', _arrival_mode: form.arrival_mode || 'walk_in', _assigned_officer: user.id } as never); error = result.error;
        } else if (tab === 'theatre') {
          const result = await supabase.rpc('create_theatre_case', { _patient_id: patientId, _procedure_name: form.procedure_name, _scheduled_start: form.scheduled_start || null, _theatre_name: form.theatre_name || null, _urgency: form.urgency || 'elective', _surgeon_id: user.id } as never); error = result.error;
        } else if (tab === 'transfusion') {
          const result = await supabase.rpc('create_transfusion_record', { _patient_id: patientId, _blood_product: form.blood_product, _unit_identifier: form.unit_identifier, _blood_group: form.blood_group || null, _consent_confirmed: form.consent === 'true' } as never); error = result.error;
        } else {
          const result = await supabase.rpc('create_insurance_claim_draft', { _patient_id: patientId, _payer_name: form.payer_name, _member_number: form.member_number || null, _amount_claimed: Number(form.amount_claimed || 0), _invoice_id: null } as never); error = result.error;
        }
      }
      if (error) throw error;
      toast({ title: 'Saved', description: 'Record created successfully.' }); if (tab === 'capacity') notifyMasterDataChanged('wards'); setForm({}); setPatientId(''); await load();
    } catch (error) { toast({ title: 'Save failed', description: error instanceof Error ? error.message : 'Please review the form.', variant: 'destructive' }); }
    finally { setBusy(false); }
  };

  const transition = async (id: string, status: string) => {
    setBusy(true);
    try {
      let error: null | { message: string } = null;
      if (tab === 'emergency') error = (await supabase.rpc('transition_emergency_case', { _case_id: id, _status: status, _disposition: status === 'discharged' ? 'Discharged from emergency' : status === 'referred' ? 'Referred for further care' : status === 'left_without_being_seen' ? 'Left without being seen' : null } as never)).error;
      else if (tab === 'theatre') error = (await supabase.rpc('transition_theatre_case', { _case_id: id, _status: status, _cancellation_reason: status === 'cancelled' || status === 'postponed' ? 'Status changed from clinical operations' : null } as never)).error;
      else if (tab === 'transfusion') error = (await supabase.rpc('record_transfusion_event', { _record_id: id, _status: status, _reaction_observed: false, _reaction_notes: null } as never)).error;
      else if (tab === 'insurance') error = (await supabase.rpc('transition_insurance_claim_canonical', { _claim_id: id, _status: status, _amount_approved: null, _amount_paid: null, _rejection_reason: status === 'rejected' ? 'Rejected in claims workflow' : null, _notes: status === 'rejected' ? 'Rejected in claims workflow' : 'Status transition from claims queue' } as never)).error;
      if (error) throw error;
      toast({ title: 'Status updated' }); await load();
    } catch (error) { toast({ title: 'Transition failed', description: error instanceof Error ? error.message : 'Workflow transition failed.', variant: 'destructive' }); }
    finally { setBusy(false); }
  };

  const label = (row: Row) => String(row.name || row.problem || row.chief_complaint || row.procedure_name || row.blood_product || row.payer_name || 'Operational record');

  if (allowedTabs.length === 0) return <div className="rounded-xl border bg-card p-6"><h1 className="text-xl font-semibold">Clinical Operations</h1><p className="mt-2 text-sm text-muted-foreground">Your current role does not have an operational workspace assigned.</p></div>;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3"><div><h1 className="text-2xl font-heading font-bold">Clinical Operations</h1><p className="text-sm text-muted-foreground">Enterprise workflows for capacity, nursing, emergency, theatre, transfusion and insurance.</p></div><button onClick={() => void load()} className="rounded-md border p-2" aria-label="Refresh" disabled={busy}><RefreshCw className="w-4 h-4" /></button></div>
      <div className="card-medical p-4"><div className="mb-3 text-sm font-semibold">Clinical workflow access</div><div className="flex flex-wrap gap-2"><Link to="/vitals" className="btn-secondary">Triage</Link><Link to="/encounters" className="btn-secondary">Encounters</Link><Link to="/theatre-board" className="btn-secondary">Theatre</Link><Link to="/transfusion-board" className="btn-secondary">Transfusion</Link></div></div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-6">{tabs.filter(([id]) => allowedTabs.includes(id)).map(([id, labelText, Icon]) => <button key={id} onClick={() => { setTab(id); setForm({}); setPatientId(''); }} className={`min-w-0 rounded-lg border p-3 text-left text-sm ${tab === id ? 'bg-primary text-primary-foreground' : 'bg-card hover:bg-muted'}`}><Icon className="mb-2 h-5 w-5" /><span className="block truncate">{labelText}</span></button>)}</div>
      <div className="space-y-4 rounded-xl border bg-card p-5">
        {tab !== 'capacity' && <select value={patientId} onChange={(event) => setPatientId(event.target.value)} className="w-full rounded-md border bg-background p-2"><option value="">Select patient</option>{patients.map((patient) => <option key={patient.id} value={patient.id}>{patient.patient_code} — {patient.first_name} {patient.last_name}</option>)}</select>}
        {tab === 'capacity' && <div className="grid grid-cols-1 gap-3 md:grid-cols-4"><input placeholder="Ward name" value={form.name || ''} onChange={(event) => set('name', event.target.value)} className="rounded-md border bg-background p-2" /><input placeholder="Ward code" value={form.code || ''} onChange={(event) => set('code', event.target.value)} className="rounded-md border bg-background p-2" /><input placeholder="Specialty" value={form.specialty || ''} onChange={(event) => set('specialty', event.target.value)} className="rounded-md border bg-background p-2" /><select value={form.gender_policy || 'mixed'} onChange={(event) => set('gender_policy', event.target.value)} className="rounded-md border bg-background p-2"><option>mixed</option><option>male</option><option>female</option></select></div>}
        {tab === 'nursing' && <div className="grid gap-3"><input placeholder="Nursing problem" value={form.problem || ''} onChange={(event) => set('problem', event.target.value)} className="rounded-md border bg-background p-2" /><input placeholder="Goal / expected outcome" value={form.goal || ''} onChange={(event) => set('goal', event.target.value)} className="rounded-md border bg-background p-2" /><textarea placeholder="Interventions" value={form.interventions || ''} onChange={(event) => set('interventions', event.target.value)} className="rounded-md border bg-background p-2" /><select value={form.priority || 'routine'} onChange={(event) => set('priority', event.target.value)} className="rounded-md border bg-background p-2"><option>routine</option><option>high</option><option>critical</option></select></div>}
        {tab === 'emergency' && <div className="grid grid-cols-1 gap-3 md:grid-cols-3"><textarea placeholder="Chief complaint" value={form.complaint || ''} onChange={(event) => set('complaint', event.target.value)} className="min-h-20 rounded-md border bg-background p-2" /><select value={form.acuity || 'urgent'} onChange={(event) => set('acuity', event.target.value)} className="rounded-md border bg-background p-2"><option>resuscitation</option><option>emergency</option><option>urgent</option><option>less_urgent</option><option>non_urgent</option></select><select value={form.arrival_mode || 'walk_in'} onChange={(event) => set('arrival_mode', event.target.value)} className="rounded-md border bg-background p-2"><option>walk_in</option><option>ambulance</option><option>referral</option><option>other</option></select></div>}
        {tab === 'theatre' && <div className="grid grid-cols-1 gap-3 md:grid-cols-3"><input placeholder="Procedure name" value={form.procedure_name || ''} onChange={(event) => set('procedure_name', event.target.value)} className="rounded-md border bg-background p-2" /><input placeholder="Theatre name" value={form.theatre_name || ''} onChange={(event) => set('theatre_name', event.target.value)} className="rounded-md border bg-background p-2" /><input type="datetime-local" value={form.scheduled_start || ''} onChange={(event) => set('scheduled_start', event.target.value)} className="rounded-md border bg-background p-2" /></div>}
        {tab === 'transfusion' && <div className="grid grid-cols-1 gap-3 md:grid-cols-2"><input placeholder="Blood product" value={form.blood_product || ''} onChange={(event) => set('blood_product', event.target.value)} className="rounded-md border bg-background p-2" /><input placeholder="Unit identifier" value={form.unit_identifier || ''} onChange={(event) => set('unit_identifier', event.target.value)} className="rounded-md border bg-background p-2" /><input placeholder="Documented blood group" value={form.blood_group || ''} onChange={(event) => set('blood_group', event.target.value)} className="rounded-md border bg-background p-2" /><select value={form.consent || 'false'} onChange={(event) => set('consent', event.target.value)} className="rounded-md border bg-background p-2"><option value="false">Consent not confirmed</option><option value="true">Consent confirmed</option></select></div>}
        {tab === 'insurance' && <div className="grid grid-cols-1 gap-3 md:grid-cols-3"><input placeholder="Payer / insurer" value={form.payer_name || ''} onChange={(event) => set('payer_name', event.target.value)} className="rounded-md border bg-background p-2" /><input placeholder="Member number" value={form.member_number || ''} onChange={(event) => set('member_number', event.target.value)} className="rounded-md border bg-background p-2" /><input type="number" min="0" step="0.01" placeholder="Amount claimed" value={form.amount_claimed || ''} onChange={(event) => set('amount_claimed', event.target.value)} className="rounded-md border bg-background p-2" /></div>}
        <button disabled={busy} onClick={() => void save()} className="w-full rounded-md bg-primary px-4 py-2 text-primary-foreground disabled:opacity-50 sm:w-auto">{busy ? 'Saving…' : 'Save record'}</button>
      </div>
      <div className="rounded-xl border bg-card p-5"><div className="mb-4 flex items-center gap-2"><Activity className="h-5 w-5" /><h2 className="font-semibold">Recent records</h2></div>{rows.length === 0 ? <p className="text-sm text-muted-foreground">No records yet.</p> : <div className="space-y-2">{rows.slice(0, 12).map((row, index) => <div key={String(row.id || index)} className="rounded-lg border p-3"><div className="flex flex-wrap items-center justify-between gap-2"><div className="min-w-0"><div className="truncate font-medium">{label(row)}</div><div className="text-xs text-muted-foreground">{String(row.status || row.priority || row.urgency || 'Recorded')} · {row.created_at ? new Date(String(row.created_at)).toLocaleString() : '—'}</div></div>{(tab === 'emergency' || tab === 'theatre' || tab === 'transfusion' || tab === 'insurance') && row.id && <select disabled={busy} value="" onChange={(event) => { if (event.target.value) void transition(String(row.id), event.target.value); }} className="w-full rounded-md border bg-background px-2 py-1 text-xs sm:w-auto"><option value="">Change status…</option>{transitions[tab].filter((status) => status !== row.status).map((status) => <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>)}</select>}</div></div>)}</div>}</div>
      <p className="text-xs text-muted-foreground">Only documented information is stored. Clinical transitions are enforced by server-side workflow functions; the system does not infer diagnoses, compatibility or treatment decisions.</p>
    </div>
  );
}
