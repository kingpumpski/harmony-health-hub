import { useCallback, useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { Activity, ArrowRightLeft, BedDouble, CalendarClock, FileCheck2, Pill, RefreshCw, ShieldCheck, Siren, Stethoscope, Syringe } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { getPatientById } from '@/lib/healthApi';

const dateTime = (value?: string | null) => value ? new Date(value).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : '—';
const label = (value?: string | null) => value ? value.replaceAll('_', ' ') : '—';

type TimelineItem = { id: string; kind: string; title: string; status?: string | null; detail?: string | null; at?: string | null };

function Section({ title, icon: Icon, children }: { title: string; icon: React.ElementType; children: React.ReactNode }) {
  return <section className="card-medical p-5 space-y-3"><h2 className="flex items-center gap-2 text-lg font-semibold"><Icon className="h-5 w-5" />{title}</h2>{children}</section>;
}

export default function PatientCareContinuity() {
  const { patientId } = useParams<{ patientId: string }>();
  const [patient, setPatient] = useState<any>(null);
  const [items, setItems] = useState<TimelineItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [failedSections, setFailedSections] = useState<string[]>([]);

  const load = useCallback(async () => {
    if (!patientId) return;
    setLoading(true);
    try {
      const patientResult = await getPatientById(patientId);
      setPatient(patientResult);
      const db = supabase as any;
      const queries: Record<string, Promise<any>> = {
        referrals: db.from('patient_referrals').select('id,destination,specialty,reason,urgency,status,appointment_date,created_at').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(50),
        transitions: db.from('care_transitions').select('id,transition_type,status,destination,summary,follow_up_required,follow_up_date,created_at,completed_at').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(50),
        mar: db.from('medication_administrations').select('id,medication_name,dose,route,status,scheduled_at,administered_at,reason').eq('patient_id', patientId).order('scheduled_at', { ascending: false }).limit(50),
        emergency: db.from('emergency_cases').select('id,chief_complaint,acuity,arrival_mode,status,arrival_at,created_at,disposition').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(50),
        theatre: db.from('theatre_cases').select('id,procedure_name,theatre_name,scheduled_start,urgency,status,anesthetist_id,created_at').eq('patient_id', patientId).order('scheduled_start', { ascending: false }).limit(50),
        transfusion: db.from('transfusion_records').select('id,blood_product,blood_unit,blood_group,status,start_at,end_at,reaction_observed,reaction_notes,created_at').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(50),
        claims: db.from('insurance_claims').select('id,payer_name,member_number,amount_claimed,amount_approved,amount_paid,status,service_from,service_to,rejection_reason,created_at').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(50),
        admissions: db.from('admissions').select('id,status,reason,admitted_at,discharged_at,discharge_summary').eq('patient_id', patientId).order('admitted_at', { ascending: false }).limit(50),
      };
      const results = await Promise.all(Object.entries(queries).map(async ([name, query]) => [name, await query] as const));
      const failed = results.filter(([, result]) => result.error).map(([name]) => name);
      setFailedSections(failed);
      const next: TimelineItem[] = [];
      const add = (rows: any[], kind: string, map: (row: any) => TimelineItem) => rows.forEach((row) => next.push(map(row)));
      const data = Object.fromEntries(results.map(([name, result]) => [name, result.data ?? []]));
      add(data.referrals ?? [], 'referral', (r) => ({ id: r.id, kind, title: `Referral to ${r.destination}`, status: r.status, detail: `${r.specialty || 'General'} · ${r.reason}`, at: r.appointment_date || r.created_at }));
      add(data.transitions ?? [], 'transition', (r) => ({ id: r.id, kind, title: `${label(r.transition_type)} transition`, status: r.status, detail: `${r.destination || 'No destination'}${r.follow_up_required ? ' · Follow-up required' : ''}`, at: r.completed_at || r.created_at }));
      add(data.mar ?? [], 'mar', (r) => ({ id: r.id, kind, title: r.medication_name, status: r.status, detail: [r.dose, r.route, r.reason].filter(Boolean).join(' · '), at: r.administered_at || r.scheduled_at }));
      add(data.emergency ?? [], 'emergency', (r) => ({ id: r.id, kind, title: `Emergency: ${r.chief_complaint}`, status: r.status, detail: `${label(r.acuity)} · ${label(r.arrival_mode)}${r.disposition ? ` · ${r.disposition}` : ''}`, at: r.arrival_at || r.created_at }));
      add(data.theatre ?? [], 'theatre', (r) => ({ id: r.id, kind, title: `Theatre: ${r.procedure_name}`, status: r.status, detail: `${r.theatre_name || 'Theatre not recorded'} · ${label(r.urgency)}`, at: r.scheduled_start || r.created_at }));
      add(data.transfusion ?? [], 'transfusion', (r) => ({ id: r.id, kind, title: `Transfusion: ${r.blood_product || 'Blood product'}`, status: r.status, detail: `${r.blood_group || 'Group not recorded'}${r.reaction_observed ? ' · Reaction observed' : ''}`, at: r.start_at || r.created_at }));
      add(data.claims ?? [], 'claim', (r) => ({ id: r.id, kind, title: `Insurance claim · ${r.payer_name}`, status: r.status, detail: `Claimed ${r.amount_claimed ?? 0} · Approved ${r.amount_approved ?? 0} · Paid ${r.amount_paid ?? 0}`, at: r.created_at }));
      add(data.admissions ?? [], 'admission', (r) => ({ id: r.id, kind, title: 'Admission', status: r.status, detail: r.reason || r.discharge_summary || 'Inpatient episode', at: r.admitted_at || r.discharged_at }));
      next.sort((a, b) => new Date(b.at || 0).getTime() - new Date(a.at || 0).getTime());
      setItems(next);
    } catch (error: any) {
      toast.error(error.message ?? 'Unable to load continuity record');
    } finally { setLoading(false); }
  }, [patientId]);

  useEffect(() => { void load(); }, [load]);

  const iconFor = (kind: string) => ({ referral: ArrowRightLeft, transition: ArrowRightLeft, mar: Pill, emergency: Siren, theatre: CalendarClock, transfusion: Syringe, claim: ShieldCheck, admission: BedDouble }[kind] || Activity);

  if (loading) return <div className="p-8 text-sm text-muted-foreground">Loading care continuity…</div>;
  if (!patient) return <div className="p-8 text-sm text-muted-foreground">Patient record not found.</div>;

  return <div className="space-y-5 animate-fade-in">
    <header className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
      <div><div className="flex flex-wrap items-center gap-2"><Link to={`/patients/${patient.id}`} className="text-sm text-primary hover:underline">Patient Hub</Link><span className="text-muted-foreground">/</span><span className="text-sm text-muted-foreground">Care Continuity</span></div><h1 className="mt-1 text-2xl font-heading font-bold">{patient.first_name} {patient.last_name}</h1><p className="text-sm text-muted-foreground">Longitudinal care, transitions, medication, emergency, theatre, transfusion and insurance history.</p></div>
      <button onClick={() => void load()} className="btn-secondary inline-flex items-center justify-center gap-2"><RefreshCw className="h-4 w-4" />Refresh</button>
    </header>

    {failedSections.length > 0 && <div className="rounded-xl border border-amber-300/50 bg-amber-50/50 p-3 text-sm text-muted-foreground">Some optional continuity sources are unavailable: {failedSections.join(', ')}. Available clinical history remains visible.</div>}

    <Section title="Longitudinal care timeline" icon={FileCheck2}>
      {items.length ? <div className="space-y-3">{items.map((item) => { const Icon = iconFor(item.kind); return <article key={`${item.kind}-${item.id}`} className="flex gap-3 rounded-xl border p-4"><div className="mt-0.5 rounded-full bg-muted p-2 shrink-0"><Icon className="h-4 w-4" /></div><div className="min-w-0 flex-1"><div className="flex flex-wrap items-start justify-between gap-2"><div><h3 className="font-medium">{item.title}</h3><p className="text-sm text-muted-foreground">{item.detail || 'No additional details recorded.'}</p></div><span className="rounded-full border px-2 py-1 text-xs capitalize">{label(item.status)}</span></div><p className="mt-2 text-xs text-muted-foreground">{dateTime(item.at)}</p></div></article>; })}</div> : <p className="rounded-xl border border-dashed p-6 text-sm text-muted-foreground">No continuity events recorded yet.</p>}
    </Section>

    <div className="grid gap-4 md:grid-cols-2">
      <Section title="Clinical safety" icon={Stethoscope}><p className="text-sm">Allergy alerts: <strong>{patient.allergies || 'None recorded'}</strong></p><p className="text-sm">Blood group: <strong>{patient.blood_group || 'Not recorded'}</strong></p><p className="text-sm">Genotype: <strong>{patient.genotype || 'Not recorded'}</strong></p><p className="text-sm">Chronic conditions: <strong>{patient.chronic_conditions || 'None recorded'}</strong></p></Section>
      <Section title="Operational follow-through" icon={Activity}><div className="flex flex-wrap gap-2"><Link to="/care-transitions" className="btn-secondary">Care transitions</Link><Link to="/medications" className="btn-secondary">Medication administration</Link><Link to="/emergency-board" className="btn-secondary">Emergency board</Link><Link to="/theatre-board" className="btn-secondary">Theatre board</Link><Link to="/transfusion-board" className="btn-secondary">Transfusion board</Link><Link to="/insurance-claims" className="btn-secondary">Insurance claims</Link></div></Section>
    </div>
  </div>;
}
