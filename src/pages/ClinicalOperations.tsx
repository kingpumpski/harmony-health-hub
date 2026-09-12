import { useEffect, useMemo, useState } from 'react';
import { Activity, BedDouble, ClipboardList, Droplets, HeartPulse, ShieldCheck, Siren, Stethoscope } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

type Tab = 'capacity' | 'nursing' | 'emergency' | 'theatre' | 'transfusion' | 'insurance';
type Patient = { id: string; patient_code: string; first_name: string; last_name: string };

const tabs: { id: Tab; label: string; icon: React.ElementType }[] = [
  { id: 'capacity', label: 'Ward & Beds', icon: BedDouble },
  { id: 'nursing', label: 'Nursing', icon: ClipboardList },
  { id: 'emergency', label: 'Emergency', icon: Siren },
  { id: 'theatre', label: 'Theatre', icon: Stethoscope },
  { id: 'transfusion', label: 'Transfusion', icon: Droplets },
  { id: 'insurance', label: 'Insurance', icon: ShieldCheck },
];

const patientName = (p: Patient) => `${p.patient_code} — ${p.first_name} ${p.last_name}`;

export default function ClinicalOperations() {
  const { user } = useAuth();
  const [tab, setTab] = useState<Tab>('capacity');
  const [patients, setPatients] = useState<Patient[]>([]);
  const [rows, setRows] = useState<any[]>([]);
  const [patientId, setPatientId] = useState('');
  const [busy, setBusy] = useState(false);
  const [ward, setWard] = useState({ name: '', code: '', department: '', floor: '' });
  const [bed, setBed] = useState({ ward_id: '', bed_number: '', bed_type: 'standard' });
  const [care, setCare] = useState({ problem: '', goal: '', interventions: '', priority: 'routine' });
  const [handover, setHandover] = useState({ summary: '', tasks: '', risks: '', escalation: false });
  const [emergency, setEmergency] = useState({ complaint: '', priority: 'urgent', arrival_mode: 'walk_in' });
  const [theatre, setTheatre] = useState({ procedure_name: '', theatre: '', scheduled_at: '', consent: false });
  const [blood, setBlood] = useState({ component: 'red_cells', unit_identifier: '', blood_group: '', consent: false });
  const [insurance, setInsurance] = useState({ payer_name: '', policy_number: '', eligibility_status: 'pending', claim_status: 'draft', claim_amount: '' });

  const loadPatients = async () => {
    const { data } = await supabase.from('patients').select('id,patient_code,first_name,last_name').order('created_at', { ascending: false }).limit(300);
    setPatients((data ?? []) as Patient[]);
  };
  const loadRows = async () => {
    const table = { capacity: 'wards', nursing: 'nursing_care_plans', emergency: 'emergency_cases', theatre: 'theatre_cases', transfusion: 'transfusion_records', insurance: 'insurance_cases' }[tab];
    const { data, error } = await supabase.from(table as never).select('*').order('created_at', { ascending: false }).limit(50);
    if (error) toast({ title: 'Unable to load workspace', description: error.message, variant: 'destructive' });
    setRows((data ?? []) as any[]);
  };
  useEffect(() => { void loadPatients(); }, []);
  useEffect(() => { void loadRows(); }, [tab]);

  const submit = async () => {
    if (!user) return;
    setBusy(true);
    try {
      let table = ''; let payload: Record<string, unknown> = {};
      if (tab === 'capacity') {
        if (!ward.name || !ward.code) throw new Error('Ward name and code are required.');
        const { data, error } = await supabase.from('wards').insert({ ...ward }).select().single();
        if (error) throw error;
        setWard({ name: '', code: '', department: '', floor: '' });
        if (data) setRows((r) => [data, ...r]);
      } else {
        if (!patientId) throw new Error('Select a patient first.');
        if (tab === 'nursing') { table = 'nursing_care_plans'; payload = { patient_id: patientId, problem: care.problem, goal: care.goal, interventions: care.interventions, priority: care.priority, created_by: user.id }; }
        if (tab === 'emergency') { table = 'emergency_cases'; payload = { patient_id: patientId, chief_complaint: emergency.complaint, triage_priority: emergency.priority, arrival_mode: emergency.arrival_mode, assigned_officer: user.id }; }
        if (tab === 'theatre') { table = 'theatre_cases'; payload = { patient_id: patientId, procedure_name: theatre.procedure_name, theatre: theatre.theatre, scheduled_at: theatre.scheduled_at || null, consent_confirmed: theatre.consent, created_by: user.id }; }
        if (tab === 'transfusion') { table = 'transfusion_records'; payload = { patient_id: patientId, component: blood.component, unit_identifier: blood.unit_identifier, blood_group: blood.blood_group, consent_confirmed: blood.consent }; }
        if (tab === 'insurance') { table = 'insurance_cases'; payload = { patient_id: patientId, payer_name: insurance.payer_name, policy_number: insurance.policy_number, eligibility_status: insurance.eligibility_status, claim_status: insurance.claim_status, claim_amount: Number(insurance.claim_amount || 0) }; }
        if (tab === 'nursing' && (!care.problem || !care.goal)) throw new Error('Nursing problem and goal are required.');
        if (tab === 'emergency' && !emergency.complaint) throw new Error('Chief complaint is required.');
        if (tab === 'theatre' && !theatre.procedure_name) throw new Error('Procedure name is required.');
        if (tab === 'insurance' && !insurance.payer_name) throw new Error('Payer name is required.');
        const { error } = await supabase.from(table as never).insert(payload as never);
        if (error) throw error;
      }
      toast({ title: 'Saved', description: 'The clinical operations record was saved.' });
      await loadRows();
    } catch (e) { toast({ title: 'Save failed', description: e instanceof Error ? e.message : 'Please try again.', variant: 'destructive' }); }
    finally { setBusy(false); }
  };

  const summary = useMemo(() => rows.slice(0, 8), [rows]);
  return <div className="space-y-6">
    <div><h1 className="text-2xl font-heading font-bold">Clinical Operations</h1><p className="text-sm text-muted-foreground">Enterprise workflows for capacity, nursing continuity, emergency care, theatre, transfusion and insurance.</p></div>
    <div className="grid grid-cols-2 md:grid-cols-6 gap-2">{tabs.map((t) => { const I = t.icon; return <button key={t.id} onClick={() => setTab(t.id)} className={`rounded-lg border p-3 text-left text-sm ${tab === t.id ? 'bg-primary text-primary-foreground' : 'bg-card hover:bg-muted'}`}><I className="w-5 h-5 mb-2" />{t.label}</button>; })}</div>
    <div className="rounded-xl border bg-card p-5 space-y-4">
      {tab !== 'capacity' && <select value={patientId} onChange={e => setPatientId(e.target.value)} className="w-full rounded-md border bg-background p-2"><option value="">Select patient</option>{patients.map(p => <option key={p.id} value={p.id}>{patientName(p)}</option>)}</select>}
      {tab === 'capacity' && <div className="grid md:grid-cols-4 gap-3">{Object.entries(ward).map(([k,v]) => <input key={k} value={v} onChange={e => setWard(w => ({...w,[k]:e.target.value}))} placeholder={k.replace('_',' ')} className="rounded-md border bg-background p-2" />)}</div>}
      {tab === 'nursing' && <div className="grid gap-3"><input value={care.problem} onChange={e=>setCare({...care,problem:e.target.value})} placeholder="Nursing problem" className="rounded-md border bg-background p-2"/><input value={care.goal} onChange={e=>setCare({...care,goal:e.target.value})} placeholder="Goal / expected outcome" className="rounded-md border bg-background p-2"/><textarea value={care.interventions} onChange={e=>setCare({...care,interventions:e.target.value})} placeholder="Interventions" className="rounded-md border bg-background p-2"/><select value={care.priority} onChange={e=>setCare({...care,priority:e.target.value})} className="rounded-md border bg-background p-2"><option>routine</option><option>high</option><option>critical</option></select></div>}
      {tab === 'emergency' && <div className="grid md:grid-cols-3 gap-3"><input value={emergency.complaint} onChange={e=>setEmergency({...emergency,complaint:e.target.value})} placeholder="Chief complaint" className="rounded-md border bg-background p-2"/><select value={emergency.priority} onChange={e=>setEmergency({...emergency,priority:e.target.value})} className="rounded-md border bg-background p-2"><option>critical</option><option>urgent</option><option>moderate</option><option>routine</option></select><select value={emergency.arrival_mode} onChange={e=>setEmergency({...emergency,arrival_mode:e.target.value})} className="rounded-md border bg-background p-2"><option>walk_in</option><option>ambulance</option><option>referral</option><option>other</option></select></div>}
      {tab === 'theatre' && <div className="grid md:grid-cols-3 gap-3"><input value={theatre.procedure_name} onChange={e=>setTheatre({...theatre,procedure_name:e.target.value})} placeholder="Procedure" className="rounded-md border bg-background p-2"/><input value={theatre.theatre} onChange={e=>setTheatre({...theatre,theatre:e.target.value})} placeholder="Theatre" className="rounded-md border bg-background p-2"/><input type="datetime-local" value={theatre.scheduled_at} onChange={e=>setTheatre({...theatre,scheduled_at:e.target.value})} className="rounded-md border bg-background p-2"/><label className="flex gap-2 items-center text-sm"><input type="checkbox" checked={theatre.consent} onChange={e=>setTheatre({...theatre,consent:e.target.checked})}/> Consent confirmed</label></div>}
      {tab === 'transfusion' && <div className="grid md:grid-cols-3 gap-3"><select value={blood.component} onChange={e=>setBlood({...blood,component:e.target.value})} className="rounded-md border bg-background p-2"><option>red_cells</option><option>platelets</option><option>plasma</option><option>cryoprecipitate</option><option>whole_blood</option></select><input value={blood.unit_identifier} onChange={e=>setBlood({...blood,unit_identifier:e.target.value})} placeholder="Unit identifier" className="rounded-md border bg-background p-2"/><input value={blood.blood_group} onChange={e=>setBlood({...blood,blood_group:e.target.value})} placeholder="Documented blood group" className="rounded-md border bg-background p-2"/><label className="flex gap-2 items-center text-sm"><input type="checkbox" checked={blood.consent} onChange={e=>setBlood({...blood,consent:e.target.checked})}/> Consent confirmed</label></div>}
      {tab === 'insurance' && <div className="grid md:grid-cols-3 gap-3"><input value={insurance.payer_name} onChange={e=>setInsurance({...insurance,payer_name:e.target.value})} placeholder="Payer / insurer" className="rounded-md border bg-background p-2"/><input value={insurance.policy_number} onChange={e=>setInsurance({...insurance,policy_number:e.target.value})} placeholder="Policy number" className="rounded-md border bg-background p-2"/><select value={insurance.eligibility_status} onChange={e=>setInsurance({...insurance,eligibility_status:e.target.value})} className="rounded-md border bg-background p-2"><option>pending</option><option>eligible</option><option>ineligible</option><option>expired</option></select><select value={insurance.claim_status} onChange={e=>setInsurance({...insurance,claim_status:e.target.value})} className="rounded-md border bg-background p-2"><option>draft</option><option>submitted</option><option>under_review</option><option>approved</option><option>rejected</option><option>paid</option><option>appealed</option></select><input type="number" min="0" value={insurance.claim_amount} onChange={e=>setInsurance({...insurance,claim_amount:e.target.value})} placeholder="Claim amount" className="rounded-md border bg-background p-2"/></div>}
      <button disabled={busy} onClick={submit} className="rounded-md bg-primary px-4 py-2 text-primary-foreground disabled:opacity-50">{busy ? 'Saving…' : 'Save record'}</button>
    </div>
    <div className="rounded-xl border bg-card p-5"><div className="flex items-center gap-2 mb-4"><Activity className="w-5 h-5"/><h2 className="font-semibold">Recent records</h2></div><div className="space-y-2">{summary.length === 0 ? <p className="text-sm text-muted-foreground">No records yet.</p> : summary.map((r,i)=><div key={r.id ?? i} className="rounded-lg border p-3 text-sm"><div className="font-medium">{r.procedure_name || r.problem || r.chief_complaint || r.payer_name || r.component || r.name || 'Operational record'}</div><div className="text-muted-foreground mt-1">{r.status || r.claim_status || r.eligibility_status || r.priority || r.code || 'Recorded'} · {r.created_at ? new Date(r.created_at).toLocaleString() : '—'}</div></div>)}</div></div>
    <div className="rounded-lg bg-muted/50 p-3 text-xs text-muted-foreground flex gap-2"><HeartPulse className="w-4 h-4 shrink-0"/> Clinical fields represent documented information only. The workspace does not infer diagnoses or replace clinician judgement.</div>
  </div>;
}
