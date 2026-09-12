import { useCallback, useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { Activity, ArrowRightLeft, BedDouble, CalendarClock, FileCheck2, Pill, RefreshCw, ShieldCheck, Siren, Stethoscope, Syringe } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { getPatientById } from '@/lib/healthApi';

const dateTime = (value?: string | null) => value ? new Date(value).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : '—';
const label = (value?: string | null) => value ? value.replaceAll('_', ' ') : '—';
type ContinuityRow = Record<string, unknown> & { id: string };
type ContinuityData = Record<string, unknown>;
type TimelineItem = { id: string; kind: string; title: string; status?: string | null; detail?: string | null; at?: string | null };
function Section({ title, icon: Icon, children }: { title: string; icon: React.ElementType; children: React.ReactNode }) { return <section className="card-medical p-5 space-y-3"><h2 className="flex items-center gap-2 text-lg font-semibold"><Icon className="h-5 w-5" />{title}</h2>{children}</section>; }
function asRows(value: unknown): ContinuityRow[] { return Array.isArray(value) ? value.filter((row): row is ContinuityRow => Boolean(row && typeof row === 'object' && 'id' in row)) : []; }
export default function PatientCareContinuity() {
  const { patientId } = useParams<{ patientId: string }>();
  const [patient, setPatient] = useState<Record<string, unknown> | null>(null);
  const [items, setItems] = useState<TimelineItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const load = useCallback(async () => {
    if (!patientId) return;
    setLoading(true); setErrorMessage(null);
    try {
      const patientResult = await getPatientById(patientId);
      if (!patientResult) { setPatient(null); return; }
      setPatient(patientResult as Record<string, unknown>);
      const { data, error } = await supabase.rpc('get_patient_care_continuity', { _patient_id: patientId });
      if (error) throw error;
      const continuity = (data && typeof data === 'object' ? data : {}) as ContinuityData;
      const next: TimelineItem[] = [];
      const add = (rows: ContinuityRow[], kind: string, map: (row: ContinuityRow) => TimelineItem) => rows.forEach((row) => next.push(map(row)));
      add(asRows(continuity.referrals), 'referral', (r) => ({ id: r.id, kind, title: `Referral to ${String(r.destination ?? 'destination')}`, status: r.status ? String(r.status) : null, detail: `${String(r.specialty ?? 'General')} · ${String(r.reason ?? 'No reason recorded')}`, at: String(r.appointment_date ?? r.created_at ?? '') }));
      add(asRows(continuity.transitions), 'transition', (r) => ({ id: r.id, kind, title: `${label(r.transition_type ? String(r.transition_type) : null)} transition`, status: r.status ? String(r.status) : null, detail: `${String(r.destination ?? 'No destination')}${r.follow_up_required ? ' · Follow-up required' : ''}`, at: String(r.completed_at ?? r.created_at ?? '') }));
      add(asRows(continuity.mar), 'mar', (r) => ({ id: r.id, kind, title: String(r.medication_name ?? 'Medication'), status: r.status ? String(r.status) : null, detail: [r.dose, r.route, r.reason].filter(Boolean).map(String).join(' · '), at: String(r.administered_at ?? r.scheduled_at ?? '') }));
      add(asRows(continuity.emergency), 'emergency', (r) => ({ id: r.id, kind, title: `Emergency: ${String(r.chief_complaint ?? 'Unspecified complaint')}`, status: r.status ? String(r.status) : null, detail: `${label(r.acuity ? String(r.acuity) : null)} · ${label(r.arrival_mode ? String(r.arrival_mode) : null)}${r.disposition ? ` · ${String(r.disposition)}` : ''}`, at: String(r.arrival_time ?? r.created_at ?? '') }));
      add(asRows(continuity.theatre), 'theatre', (r) => ({ id: r.id, kind, title: `Theatre: ${String(r.procedure_name ?? 'Procedure')}`, status: r.status ? String(r.status) : null, detail: `${String(r.theatre_name ?? 'Theatre not recorded')} · ${label(r.urgency ? String(r.urgency) : null)}`, at: String(r.scheduled_start ?? r.created_at ?? '') }));
      add(asRows(continuity.transfusion), 'transfusion', (r) => ({ id: r.id, kind, title: `Transfusion: ${String(r.blood_product ?? 'Blood product')}`, status: r.status ? String(r.status) : null, detail: `${String(r.blood_group ?? 'Group not recorded')} · Unit ${String(r.unit_identifier ?? 'not recorded')}${r.reaction_observed ? ' · Reaction observed' : ''}`, at: String(r.started_at ?? r.created_at ?? '') }));
      add(asRows(continuity.claims), 'claim', (r) => ({ id: r.id, kind, title: `Insurance claim · ${String(r.payer_name ?? 'Payer')}`, status: r.status ? String(r.status) : null, detail: `Claimed ${String(r.amount_claimed ?? 0)} · Approved ${String(r.amount_approved ?? 0)} · Paid ${String(r.amount_paid ?? 0)}`, at: String(r.created_at ?? '') }));
      add(asRows(continuity.admissions), 'admission', (r) => ({ id: r.id, kind, title: 'Admission', status: r.status ? String(r.status) : null, detail: String(r.reason ?? r.discharge_summary ?? 'Inpatient episode'), at: String(r.admitted_at ?? r.discharged_at ?? '') }));
      next.sort((a, b) => new Date(b.at || 0).getTime() - new Date(a.at || 0).getTime()); setItems(next);
    } catch (error: unknown) { const message = error instanceof Error ? error.message : 'Unable to load continuity record'; setErrorMessage(message); toast.error(message); }
    finally { setLoading(false); }
  }, [patientId]);
  useEffect(() => { void load(); }, [load]);
  const iconFor = (kind: string) => ({ referral: ArrowRightLeft, transition: ArrowRightLeft, mar: Pill, emergency: Siren, theatre: CalendarClock, transfusion: Syringe, claim: ShieldCheck, admission: BedDouble }[kind] || Activity);
  if (loading) return <div className="p-8 text-sm text-muted-foreground">Loading care continuity…</div>;
  if (!patient) return <div className="p-8 text-sm text-muted-foreground">Patient record not found.</div>;
  const firstName = String(patient.first_name ?? ''); const lastName = String(patient.last_name ?? ''); const patientRecordId = String(patient.id ?? patientId ?? '');
  return <div className="space-y-5 animate-fade-in">
    <header className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between"><div><div className="flex flex-wrap items-center gap-2"><Link to={`/patients/${patientRecordId}`} className="text-sm text-primary hover:underline">Patient Hub</Link><span className="text-muted-foreground">/</span><span className="text-sm text-muted-foreground">Care Continuity</span></div><h1 className="mt-1 text-2xl font-heading font-bold">{firstName} {lastName}</h1><p className="text-sm text-muted-foreground">Longitudinal care, transitions, medication, emergency, theatre, transfusion and insurance history.</p></div><button onClick={() => void load()} className="btn-secondary inline-flex items-center justify-center gap-2"><RefreshCw className="h-4 w-4" />Refresh</button></header>
    {errorMessage && <div className="rounded-xl border border-amber-300/50 bg-amber-50/50 p-3 text-sm text-muted-foreground">Some continuity history could not be loaded. Please refresh or contact an administrator if the problem persists.</div>}
    <Section title="Longitudinal care timeline" icon={FileCheck2}>{items.length ? <div className="space-y-3">{items.map((item) => { const Icon = iconFor(item.kind); return <article key={`${item.kind}-${item.id}`} className="flex gap-3 rounded-xl border p-4"><div className="mt-0.5 rounded-full bg-muted p-2 shrink-0"><Icon className="h-4 w-4" /></div><div className="min-w-0 flex-1"><div className="flex flex-wrap items-start justify-between gap-2"><div><h3 className="font-medium">{item.title}</h3><p className="text-sm text-muted-foreground">{item.detail || 'No additional details recorded.'}</p></div><span className="rounded-full border px-2 py-1 text-xs capitalize">{label(item.status)}</span></div><p className="mt-2 text-xs text-muted-foreground">{dateTime(item.at)}</p></div></article>; })}</div> : <p className="rounded-xl border border-dashed p-6 text-sm text-muted-foreground">No continuity events recorded yet.</p>}</Section>
    <div className="grid gap-4 md:grid-cols-2"><Section title="Clinical safety" icon={Stethoscope}><p className="text-sm">Allergy alerts: <strong>{String(patient.allergies || 'None recorded')}</strong></p><p className="text-sm">Blood group: <strong>{String(patient.blood_group || 'Not recorded')}</strong></p><p className="text-sm">Genotype: <strong>{String(patient.genotype || 'Not recorded')}</strong></p><p className="text-sm">Chronic conditions: <strong>{String(patient.chronic_conditions || 'None recorded')}</strong></p></Section><Section title="Operational follow-through" icon={Activity}><div className="flex flex-wrap gap-2"><Link to="/care-transitions" className="btn-secondary">Care transitions</Link><Link to="/medications" className="btn-secondary">Medication administration</Link><Link to="/emergency-board" className="btn-secondary">Emergency board</Link><Link to="/theatre-board" className="btn-secondary">Theatre board</Link><Link to="/transfusion-board" className="btn-secondary">Transfusion board</Link><Link to="/insurance-claims" className="btn-secondary">Insurance claims</Link></div></Section></div>
  </div>;
}
