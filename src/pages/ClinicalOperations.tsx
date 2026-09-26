import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { useCallback, useEffect, useState, type ElementType } from 'react';
import { Link } from 'react-router-dom';
import { Activity, BedDouble, ClipboardList, Droplets, RefreshCw, ShieldCheck, Siren, Stethoscope } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { searchPatientDirectory } from '@/lib/patientDirectory';
import { notifyMasterDataChanged } from '@/lib/masterDataEvents';
import { getDefaultPermissions } from '@/lib/permissions';

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
  const permissions = new Set(user?.permissions?.length ? user.permissions : (user ? getDefaultPermissions(user.role) : []));
  const workflowLinks = [
    ['Triage', '/vitals', 'triage'], ['Encounters', '/encounters', 'encounters'], ['Theatre', '/theatre-board', 'theatre'],
    ['Transfusion', '/transfusion-board', 'transfusion'], ['Maternity', '/maternity', 'maternity'], ['Radiology', '/radiology', 'radiology'],
    ['Fertility', '/fertility', 'fertility'], ['Dental', '/dental', 'dental'], ['Procedures', '/procedures', 'procedures'], ['Anaesthesia', '/anesthesia', 'anesthesia'],
  ].filter(([, , permission]) => permissions.has(permission as any));
  const [tab, setTab] = useState<Tab>(allowedTabs[0] ?? 'capacity');
  const [patients, setPatients] = useState<Patient[]>([]);
  const [rows, setRows] = useState<Row[]>([]);
  const [patientId, setPatientId] = useState('');
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState<Record<string, string>>({});
  const set = (key: string, value: string) => setForm((current) => ({ ...current, [key]: value }));
  const workspaceModule = tab === 'capacity' ? 'ward' : tab === 'nursing' ? 'nursing_care' : tab;
  const canSelfAssignSurgeon = user?.roles?.includes('practitioner') ?? false;

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
    if (tab === 'capacity' && (!form.name?.trim() || !form.code?.trim())) {
      toast({ title: 'Complete required fields', description: 'Ward name and ward code are required.', variant: 'destructive' });
      return;
    }
    if (tab !== 'capacity' && !patientId) {
      toast({ title: 'Select a patient', description: 'A patient must be selected before creating this operational record.', variant: 'destructive' });
      return;
    }
    const requiredByTab: Partial<Record<Tab, string[]>> = {
      nursing: ['problem', 'goal', 'interventions'],
      emergency: ['complaint'],
      theatre: ['procedure_name'],
      transfusion: ['blood_product', 'unit_identifier'],
      insurance: ['payer_name', 'amount_claimed'],
    };
    const missing = (requiredByTab[tab] ?? []).filter((key) => !form[key]?.trim());
    if (missing.length) {
      toast({ title: 'Complete required fields', description: 'Please complete all required fields before saving.', variant: 'destructive' });
      return;
    }
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
          const result = await supabase.rpc('create_theatre_case', { _patient_id: patientId, _procedure_name: form.procedure_name, _scheduled_start: form.scheduled_start || null, _theatre_name: form.theatre_name || null, _urgency: form.urgency || 'elective', _surgeon_id: canSelfAssignSurgeon ? user.id : null } as never); error = result.error;
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
  const statusCounts = rows.reduce<Record<string, number>>((counts, row) => { const status = String(row.status || row.priority || row.urgency || 'recorded'); counts[status] = (counts[status] ?? 0) + 1; return counts; }, {});
  const topStatuses = Object.entries(statusCounts).sort(([, a], [, b]) => b - a).slice(0, 4);
  const tabDescriptions: Record<Tab, string> = { capacity: 'Ward capacity and bed-side resources', nursing: 'Care plans and nursing priorities', emergency: 'Emergency arrivals and clinical disposition', theatre: 'Procedures, scheduling and theatre flow', transfusion: 'Blood products and transfusion events', insurance: 'Claims intake and payer workflow' };

  if (allowedTabs.length === 0) return <div className="rounded-xl border bg-card p-6"><h1 className="text-xl font-semibold">Clinical Operations</h1><p className="mt-2 text-sm text-muted-foreground">Your current role does not have an operational workspace assigned.</p></div>;

  return (
    <div className="space-y-6">
      <header className="rounded-3xl border border-border bg-card p-5 shadow-sm sm:p-7">
<div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
<div><div className="mb-2 flex items-center gap-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-primary"><Activity className="h-3.5 w-3.5" /> Clinical command · Operations</div><h1 className="text-2xl font-heading font-bold tracking-tight sm:text-3xl">Clinical Operations</h1><p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">Coordinate capacity, nursing, emergency, theatre, transfusion and insurance workflows from one role-aware workspace.</p></div>
<button onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2 self-start" aria-label="Refresh clinical operations" disabled={busy}><RefreshCw className={`h-4 w-4 ${busy ? 'animate-spin' : ''}`} /> Refresh</button>
</div></header>
      <div className="card-medical rounded-2xl p-4"><div className="mb-3 flex items-center justify-between gap-3"><div><div className="text-[10px] font-semibold uppercase tracking-[0.15em] text-primary">Clinical workflow access</div><p className="mt-1 text-xs text-muted-foreground">Role-permitted entry points for the next clinical action.</p></div><span className="text-[10px] rounded-full border border-border px-2 py-1 text-muted-foreground">{workflowLinks.length} available</span></div><div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">{workflowLinks.map(([labelText, href]) => <Link key={href} to={href} className="btn-secondary">{labelText}</Link>)}</div></div>
      <section className="grid grid-cols-1 gap-3 sm:grid-cols-3" aria-label="Clinical operations snapshot">
        <div className="rounded-2xl border bg-card p-4 shadow-sm"><div className="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">Visible records</div><div className="mt-1 text-2xl font-semibold">{rows.length}</div><p className="mt-1 text-xs text-muted-foreground">Current {tabs.find(([id]) => id === tab)?.[1] ?? 'workspace'} view</p></div>
        <div className="rounded-2xl border bg-card p-4 shadow-sm"><div className="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">Top status</div><div className="mt-1 text-lg font-semibold capitalize">{topStatuses[0]?.[0]?.replaceAll('_', ' ') ?? 'No records'}</div><p className="mt-1 text-xs text-muted-foreground">{topStatuses[0]?.[1] ?? 0} record{topStatuses[0]?.[1] === 1 ? '' : 's'}</p></div>
        <div className="rounded-2xl border bg-card p-4 shadow-sm"><div className="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">Workspace focus</div><div className="mt-1 text-sm font-semibold">{tabDescriptions[tab]}</div><p className="mt-1 text-xs text-muted-foreground">Use the dedicated boards for deeper workflow actions.</p></div>
      </section>
      <div role="tablist" aria-label="Clinical operations workspaces" className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-6">{tabs.filter(([id]) => allowedTabs.includes(id)).map(([id, labelText, Icon]) => <button key={id} id={`clinical-tab-${id}`} role="tab" aria-selected={tab === id} aria-controls="clinical-operations-workspace-panel" tabIndex={tab === id ? 0 : -1} onClick={() => { setTab(id); setForm({}); setPatientId(''); }} onKeyDown={(event) => { const available = tabs.filter(([workspaceId]) => allowedTabs.includes(workspaceId)).map(([workspaceId]) => workspaceId); const index = available.indexOf(id); const next = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? (index + 1) % available.length : event.key === 'ArrowLeft' || event.key === 'ArrowUp' ? (index - 1 + available.length) % available.length : -1; if (next >= 0) { event.preventDefault(); const nextId = available[next]; setTab(nextId); requestAnimationFrame(() => document.getElementById(`clinical-tab-${nextId}`)?.focus()); } }} className={`min-w-0 rounded-xl border p-3 text-left text-sm transition-colors ${tab === id ? 'bg-primary text-primary-foreground shadow-sm' : 'bg-card hover:bg-muted'}`}><Icon aria-hidden="true" className="mb-2 h-5 w-5" /><span className="block truncate">{labelText}</span></button>)}</div>
      <div id="clinical-operations-workspace-panel" role="tabpanel" aria-labelledby={`clinical-tab-${tab}`} tabIndex={0} className="space-y-4 rounded-2xl border bg-card p-5 shadow-sm" aria-live="polite">
        {tab !== 'capacity' && <div className="space-y-1"><label htmlFor="clinical-operations-patient" className="text-sm font-medium">Patient <span className="text-destructive">*</span></label><select id="clinical-operations-patient" required value={patientId} onChange={(event) => setPatientId(event.target.value)} className="w-full rounded-md border bg-background p-2"><option value="">Select patient</option>{patients.map((patient) => <option key={patient.id} value={patient.id}>{patient.patient_code} — {patient.first_name} {patient.last_name}</option>)}</select><p className="text-xs text-muted-foreground">Select the patient associated with this operational record.</p></div>}
        {tab === 'capacity' && <div className="grid grid-cols-1 gap-3 md:grid-cols-4"><div className="space-y-1"><label htmlFor="ward-name" className="text-sm font-medium">Ward name <span className="text-destructive">*</span></label><input id="ward-name" required placeholder="Ward name" value={form.name || ''} onChange={(event) => set('name', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="ward-code" className="text-sm font-medium">Ward code <span className="text-destructive">*</span></label><input id="ward-code" required placeholder="Ward code" value={form.code || ''} onChange={(event) => set('code', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="ward-specialty" className="text-sm font-medium">Specialty</label><input id="ward-specialty" placeholder="Specialty" value={form.specialty || ''} onChange={(event) => set('specialty', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="ward-gender-policy" className="text-sm font-medium">Gender policy</label><select id="ward-gender-policy" value={form.gender_policy || 'mixed'} onChange={(event) => set('gender_policy', event.target.value)} className="w-full rounded-md border bg-background p-2"><option>mixed</option><option>male</option><option>female</option></select></div></div>}
        {tab === 'nursing' && <div className="grid gap-3"><div className="space-y-1"><label htmlFor="nursing-problem" className="text-sm font-medium">Nursing problem <span className="text-destructive">*</span></label><input id="nursing-problem" required placeholder="Nursing problem" value={form.problem || ''} onChange={(event) => set('problem', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="nursing-goal" className="text-sm font-medium">Goal / expected outcome <span className="text-destructive">*</span></label><input id="nursing-goal" required placeholder="Goal / expected outcome" value={form.goal || ''} onChange={(event) => set('goal', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="nursing-interventions" className="text-sm font-medium">Interventions <span className="text-destructive">*</span></label><textarea id="nursing-interventions" required placeholder="Interventions" value={form.interventions || ''} onChange={(event) => set('interventions', event.target.value)} className="min-h-24 w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="nursing-priority" className="text-sm font-medium">Priority</label><select id="nursing-priority" value={form.priority || 'routine'} onChange={(event) => set('priority', event.target.value)} className="w-full rounded-md border bg-background p-2"><option>routine</option><option>high</option><option>critical</option></select></div></div>}
        {tab === 'emergency' && <div className="grid grid-cols-1 gap-3 md:grid-cols-3"><div className="space-y-1"><label htmlFor="emergency-complaint" className="text-sm font-medium">Chief complaint <span className="text-destructive">*</span></label><textarea id="emergency-complaint" required placeholder="Chief complaint" value={form.complaint || ''} onChange={(event) => set('complaint', event.target.value)} className="min-h-20 w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="emergency-acuity" className="text-sm font-medium">Acuity</label><select id="emergency-acuity" value={form.acuity || 'urgent'} onChange={(event) => set('acuity', event.target.value)} className="w-full rounded-md border bg-background p-2"><option>resuscitation</option><option>emergency</option><option>urgent</option><option>less_urgent</option><option>non_urgent</option></select></div><div className="space-y-1"><label htmlFor="emergency-arrival" className="text-sm font-medium">Arrival mode</label><select id="emergency-arrival" value={form.arrival_mode || 'walk_in'} onChange={(event) => set('arrival_mode', event.target.value)} className="w-full rounded-md border bg-background p-2"><option>walk_in</option><option>ambulance</option><option>referral</option><option>other</option></select></div></div>}
        {tab === 'theatre' && <div className="grid grid-cols-1 gap-3 md:grid-cols-3"><div className="space-y-1"><label htmlFor="theatre-procedure" className="text-sm font-medium">Procedure name <span className="text-destructive">*</span></label><input id="theatre-procedure" required placeholder="Procedure name" value={form.procedure_name || ''} onChange={(event) => set('procedure_name', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="theatre-name" className="text-sm font-medium">Theatre name</label><input id="theatre-name" placeholder="Theatre name" value={form.theatre_name || ''} onChange={(event) => set('theatre_name', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="theatre-start" className="text-sm font-medium">Scheduled start</label><input id="theatre-start" type="datetime-local" value={form.scheduled_start || ''} onChange={(event) => set('scheduled_start', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div></div>}
        {tab === 'transfusion' && <div className="grid grid-cols-1 gap-3 md:grid-cols-2"><div className="space-y-1"><label htmlFor="transfusion-product" className="text-sm font-medium">Blood product <span className="text-destructive">*</span></label><input id="transfusion-product" required placeholder="Blood product" value={form.blood_product || ''} onChange={(event) => set('blood_product', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="transfusion-unit" className="text-sm font-medium">Unit identifier <span className="text-destructive">*</span></label><input id="transfusion-unit" required placeholder="Unit identifier" value={form.unit_identifier || ''} onChange={(event) => set('unit_identifier', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="transfusion-group" className="text-sm font-medium">Documented blood group</label><input id="transfusion-group" placeholder="Documented blood group" value={form.blood_group || ''} onChange={(event) => set('blood_group', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="transfusion-consent" className="text-sm font-medium">Consent status</label><select id="transfusion-consent" value={form.consent || 'false'} onChange={(event) => set('consent', event.target.value)} className="w-full rounded-md border bg-background p-2"><option value="false">Consent not confirmed</option><option value="true">Consent confirmed</option></select></div></div>}
        {tab === 'insurance' && <div className="grid grid-cols-1 gap-3 md:grid-cols-3"><div className="space-y-1"><label htmlFor="insurance-payer" className="text-sm font-medium">Payer / insurer <span className="text-destructive">*</span></label><input id="insurance-payer" required placeholder="Payer / insurer" value={form.payer_name || ''} onChange={(event) => set('payer_name', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="insurance-member" className="text-sm font-medium">Member number</label><input id="insurance-member" placeholder="Member number" value={form.member_number || ''} onChange={(event) => set('member_number', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div><div className="space-y-1"><label htmlFor="insurance-amount" className="text-sm font-medium">Amount claimed <span className="text-destructive">*</span></label><input id="insurance-amount" required type="number" min="0" step="0.01" placeholder="Amount claimed" value={form.amount_claimed || ''} onChange={(event) => set('amount_claimed', event.target.value)} className="w-full rounded-md border bg-background p-2" /></div></div>}
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"><p className="text-xs text-muted-foreground"><span className="text-destructive">*</span> Required fields. Server-side validation remains authoritative.</p><button type="button" disabled={busy} onClick={() => void save()} className="w-full rounded-md bg-primary px-4 py-2 text-primary-foreground disabled:opacity-50 sm:w-auto">{busy ? 'Saving…' : 'Save record'}</button></div>
      </div>
      <div className="rounded-2xl border bg-card p-5 shadow-sm"><div className="mb-4 flex flex-wrap items-center justify-between gap-2"><div className="flex items-center gap-2"><Activity className="h-5 w-5 text-primary" /><div><h2 className="font-semibold">Recent records</h2><p className="text-xs text-muted-foreground">Latest records available to your current operational workspace.</p></div></div><span className="rounded-full border border-border bg-muted/30 px-2.5 py-1 text-[10px] font-medium text-muted-foreground">{rows.length} loaded</span></div>{rows.length === 0 ? <p className="text-sm text-muted-foreground">No records yet.</p> : <div className="space-y-2">{rows.slice(0, 12).map((row, index) => <div key={String(row.id || index)} className="rounded-xl border p-4 transition-colors hover:bg-muted/20"><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><div className="truncate font-medium">{label(row)}</div><span className="rounded-full border border-border bg-muted/30 px-2 py-0.5 text-[10px] font-medium capitalize">{String(row.status || row.priority || row.urgency || 'recorded').replaceAll('_', ' ')}</span></div><div className="mt-1 grid grid-cols-1 gap-x-4 gap-y-1 text-xs text-muted-foreground sm:grid-cols-2"><span>Patient: {String(row.patient_code || row.patient_id || 'Not displayed')}</span><span>Created: {row.created_at ? new Date(String(row.created_at)).toLocaleString() : '—'}</span></div></div>{(tab === 'emergency' || tab === 'theatre' || tab === 'transfusion' || tab === 'insurance') && row.id && <select aria-label={'Change status for ' + label(row)} disabled={busy} value="" onChange={(event) => { if (event.target.value) void transition(String(row.id), event.target.value); }} className="w-full rounded-md border bg-background px-2 py-2 text-xs sm:w-auto"><option value="">Change status…</option>{transitions[tab].filter((status) => status !== row.status).map((status) => <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>)}</select>}</div></div>)}</div>}</div>
      <p className="text-xs text-muted-foreground">Only documented information is stored. Clinical transitions are enforced by server-side workflow functions; the system does not infer diagnoses, compatibility or treatment decisions.</p>
    </div>
  );
}
