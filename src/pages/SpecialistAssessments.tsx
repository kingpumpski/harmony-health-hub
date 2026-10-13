import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AlertTriangle, ClipboardCheck, LoaderCircle, Save } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import RefreshButton from '@/components/ui/RefreshButton';

type Specialty = 'physiotherapy' | 'ophthalmology' | 'dental' | 'dietetics';
type EncounterOption = { id: string; patient_id: string; created_at: string; principal_diagnosis: string | null; status: string | null };
const db = supabase as any;
const specialties: Record<Specialty, { title: string; table: string; role: string; fields: Array<{ name: string; label: string; kind?: string; required?: boolean }> }> = {
  physiotherapy: { title: 'Physiotherapy assessment', table: 'physio_assessments', role: 'physiotherapist', fields: [
    { name: 'assessment_type', label: 'Assessment type', kind: 'select', required: true },
    { name: 'chief_complaint', label: 'Chief complaint', kind: 'textarea', required: true },
    { name: 'pain_scale', label: 'Pain score (1–10)', kind: 'number' },
    { name: 'treatment_plan', label: 'Treatment plan', kind: 'textarea' },
    { name: 'treatment_given', label: 'Treatment delivered today', kind: 'textarea' },
    { name: 'progress_notes', label: 'Progress notes', kind: 'textarea' },
    { name: 'functional_goals', label: 'Functional goals (one per line)', kind: 'textarea' },
    { name: 'next_session_date', label: 'Next session date', kind: 'date' }
  ] },
  ophthalmology: { title: 'Ophthalmology assessment', table: 'ophthalmology_assessments', role: 'ophthalmologist', fields: [
    { name: 'visual_acuity_right', label: 'Right eye visual acuity' },
    { name: 'visual_acuity_left', label: 'Left eye visual acuity' },
    { name: 'intraocular_pressure_right', label: 'Right eye pressure (mmHg)', kind: 'number' },
    { name: 'intraocular_pressure_left', label: 'Left eye pressure (mmHg)', kind: 'number' },
    { name: 'slit_lamp_findings', label: 'Slit-lamp findings', kind: 'textarea' },
    { name: 'fundoscopy_findings', label: 'Fundoscopy findings', kind: 'textarea' },
    { name: 'refraction_right', label: 'Right eye refraction' },
    { name: 'refraction_left', label: 'Left eye refraction' },
    { name: 'specialized_test_orders', label: 'Requested specialist tests (one per line)', kind: 'textarea' },
    { name: 'post_op_review_due', label: 'Post-operative review due', kind: 'date' }
  ] },
  dental: { title: 'Dental assessment', table: 'dental_assessments', role: 'dentist', fields: [
    { name: 'tooth_chart_system', label: 'Tooth numbering system', kind: 'select', required: true },
    { name: 'tooth_chart_data', label: 'Tooth chart notes (one tooth per line: tooth, finding)', kind: 'textarea' },
    { name: 'periodontal_status', label: 'Periodontal status', kind: 'textarea' },
    { name: 'oral_hygiene_instructions', label: 'Oral hygiene instructions', kind: 'textarea' },
    { name: 'procedures_performed', label: 'Procedures performed (one per line)', kind: 'textarea' },
    { name: 'pending_procedures', label: 'Planned procedures (one per line)', kind: 'textarea' }
  ] },
  dietetics: { title: 'Dietetic assessment', table: 'dietary_assessments', role: 'dietician', fields: [
    { name: 'weight_kg', label: 'Weight (kg)', kind: 'number' },
    { name: 'height_cm', label: 'Height (cm)', kind: 'number' },
    { name: 'waist_circumference_cm', label: 'Waist circumference (cm)', kind: 'number' },
    { name: 'clinical_assessment', label: 'Clinical nutrition assessment', kind: 'textarea' },
    { name: 'dietary_recall', label: 'Dietary recall (one item per line)', kind: 'textarea' },
    { name: 'nutritional_diagnosis', label: 'Nutrition diagnosis', kind: 'textarea' },
    { name: 'meal_plan', label: 'Meal plan (describe meals and timing)', kind: 'textarea' },
    { name: 'meal_plan_review_due', label: 'Meal plan review due', kind: 'date' },
    { name: 'adherence_notes', label: 'Adherence notes', kind: 'textarea' }
  ] }
};

function lines(value: string): string[] { return value.split('\n').map(v => v.trim()).filter(Boolean); }
function numericOrNull(value: string): number | null { if (!value.trim()) return null; const n = Number(value); return Number.isFinite(n) ? n : null; }

export default function SpecialistAssessments() {
  const { user } = useAuth();
  const [params] = useSearchParams();
  const initial = params.get('specialty');
  const [specialty, setSpecialty] = useState<Specialty>(initial === 'ophthalmology' || initial === 'dental' || initial === 'dietetics' ? initial : 'physiotherapy');
  const config = specialties[specialty];
  const [encounters, setEncounters] = useState<EncounterOption[]>([]);
  const [encounterId, setEncounterId] = useState('');
  const [facilityId, setFacilityId] = useState('');
  const [values, setValues] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const [facilityResult, encounterResult] = await Promise.all([
        db.rpc('current_user_facility_id'),
        db.from('encounters').select('id,patient_id,created_at,principal_diagnosis,status').order('created_at', { ascending: false }).limit(100)
      ]);
      if (facilityResult.error || !facilityResult.data) throw new Error(facilityResult.error?.message || 'No active facility is selected for this account.');
      if (encounterResult.error) throw new Error(encounterResult.error.message);
      setFacilityId(String(facilityResult.data));
      setEncounters(Array.isArray(encounterResult.data) ? encounterResult.data : []);
      setEncounterId(current => current && encounterResult.data?.some((e: EncounterOption) => e.id === current) ? current : '');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load authorized encounters.');
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => { setValues({}); setNotice(null); }, [specialty]);

  const selectedEncounter = useMemo(() => encounters.find(e => e.id === encounterId), [encounters, encounterId]);

  function change(name: string, value: string) { setValues(current => ({ ...current, [name]: value })); }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(null); setNotice(null);
    if (!user?.id) { setError('Your session has expired. Sign in again before saving clinical documentation.'); return; }
    if (!facilityId || !selectedEncounter) { setError('Select an encounter from your authorized facility before saving.'); return; }
    setSaving(true);
    try {
      const payload: Record<string, unknown> = {
        patient_id: selectedEncounter.patient_id, encounter_id: selectedEncounter.id,
        facility_id: facilityId, created_by: user.id, updated_at: new Date().toISOString()
      };
      for (const field of config.fields) {
        const value = values[field.name] ?? '';
        if (!value.trim()) continue;
        if (['pain_scale', 'weight_kg', 'height_cm', 'waist_circumference_cm'].includes(field.name)) {
          payload[field.name] = numericOrNull(value);
        } else if (['functional_goals', 'specialized_test_orders', 'procedures_performed', 'pending_procedures', 'dietary_recall'].includes(field.name)) {
          payload[field.name] = lines(value);
        } else if (field.name === 'tooth_chart_data') {
          const chart: Record<string, string> = {};
          for (const row of lines(value)) {
            const [tooth, ...finding] = row.split(',');
            if (!tooth?.trim() || !finding.join(',').trim()) throw new Error('Tooth chart lines must use “tooth number, finding”.');
            chart[tooth.trim()] = finding.join(',').trim();
          }
          payload[field.name] = chart;
        } else if (field.name === 'intraocular_pressure_right' || field.name === 'intraocular_pressure_left') {
          const key = field.name.endsWith('_right') ? 'right' : 'left';
          const current = (payload.intraocular_pressure as Record<string, unknown> | undefined) ?? {};
          current[key] = numericOrNull(value); payload.intraocular_pressure = current;
        } else if (field.name === 'refraction_right' || field.name === 'refraction_left') {
          const key = field.name.endsWith('_right') ? 'right' : 'left';
          const current = (payload.refraction as Record<string, unknown> | undefined) ?? {};
          current[key] = value.trim(); payload.refraction = current;
        } else if (field.name === 'meal_plan') {
          payload.meal_plan = { notes: value.trim() };
        } else payload[field.name] = value.trim();
      }
      if (specialty === 'dietetics') {
        const weight = numericOrNull(values.weight_kg ?? '');
        const height = numericOrNull(values.height_cm ?? '');
        if (weight && height) payload.bmi = Math.round((weight / Math.pow(height / 100, 2)) * 100) / 100;
      }
      const { error: insertError } = await db.from(config.table).insert(payload);
      if (insertError) throw new Error(insertError.message);
      setNotice('Assessment saved successfully. No billing, test order, medication or meal-service transaction was created by this form.');
      setValues({});
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Assessment could not be saved. No success was assumed.');
    } finally { setSaving(false); }
  }

  return <div className="mx-auto max-w-5xl space-y-6">
    <header className="rounded-2xl border border-border bg-card p-5 sm:p-6">
      <p className="text-xs font-semibold uppercase tracking-widest text-primary">Clinical documentation</p>
      <h1 className="mt-2 text-2xl font-bold">{config.title}</h1>
      <p className="mt-2 text-sm text-muted-foreground">Record an assessment against an existing encounter. Encounter visibility and database row-level security remain authoritative.</p>
      <div className="mt-4 flex flex-wrap items-center gap-3">
        <label className="text-sm font-medium" htmlFor="specialty">Specialty</label>
        <select id="specialty" value={specialty} onChange={e => setSpecialty(e.target.value as Specialty)} className="rounded-lg border border-input bg-background px-3 py-2 text-sm">
          <option value="physiotherapy">Physiotherapy</option><option value="ophthalmology">Ophthalmology</option><option value="dental">Dentistry</option><option value="dietetics">Dietetics</option>
        </select>
        <RefreshButton onClick={() => void load()} loading={loading} label="Refresh encounter list" />
      </div>
    </header>
    {error && <div role="alert" className="flex gap-2 rounded-xl border border-destructive/30 bg-destructive/5 p-3 text-sm"><AlertTriangle className="h-5 w-5 shrink-0" /><span>{error}</span></div>}
    {notice && <div role="status" className="rounded-xl border border-primary/30 bg-primary/5 p-3 text-sm">{notice}</div>}
    <form onSubmit={submit} className="space-y-5 rounded-2xl border border-border bg-card p-5">
      <div><label htmlFor="encounter" className="mb-2 block text-sm font-medium">Existing encounter *</label><select id="encounter" required value={encounterId} onChange={e => setEncounterId(e.target.value)} disabled={loading || saving} className="w-full rounded-lg border border-input bg-background px-3 py-2 text-sm"><option value="">Select encounter</option>{encounters.map(e => <option key={e.id} value={e.id}>{e.id.slice(0, 8).toUpperCase()} · Patient {e.patient_id.slice(0, 8).toUpperCase()} · {new Date(e.created_at).toLocaleDateString()} · {e.principal_diagnosis || e.status || 'Encounter'}</option>)}</select><p className="mt-1 text-xs text-muted-foreground">Showing up to 100 encounters visible to your current authenticated account.</p></div>
      <div className="grid gap-4 sm:grid-cols-2">
        {config.fields.map(field => <div key={field.name} className={field.kind === 'textarea' ? 'sm:col-span-2' : ''}>
          <label htmlFor={field.name} className="mb-1.5 block text-sm font-medium">{field.label}{field.required ? ' *' : ''}</label>
          {field.name === 'assessment_type' ? <select id={field.name} required={field.required} value={values[field.name] ?? 'initial'} onChange={e => change(field.name, e.target.value)} className="w-full rounded-lg border border-input bg-background px-3 py-2 text-sm"><option value="initial">Initial</option><option value="review">Review</option></select>
          : field.name === 'tooth_chart_system' ? <select id={field.name} required value={values[field.name] ?? 'FDI'} onChange={e => change(field.name, e.target.value)} className="w-full rounded-lg border border-input bg-background px-3 py-2 text-sm"><option value="FDI">FDI</option><option value="Universal">Universal</option></select>
          : field.kind === 'textarea' ? <textarea id={field.name} required={field.required} rows={3} value={values[field.name] ?? ''} onChange={e => change(field.name, e.target.value)} className="w-full rounded-lg border border-input bg-background px-3 py-2 text-sm" />
          : <input id={field.name} required={field.required} type={field.kind === 'number' ? 'number' : field.kind === 'date' ? 'date' : 'text'} min={field.name === 'pain_scale' ? 1 : undefined} max={field.name === 'pain_scale' ? 10 : undefined} step={field.kind === 'number' ? 'any' : undefined} value={values[field.name] ?? ''} onChange={e => change(field.name, e.target.value)} className="w-full rounded-lg border border-input bg-background px-3 py-2 text-sm" />}
        </div>)}
      </div>
      {specialty === 'dental' && <div className="rounded-xl border border-border p-3 text-sm text-muted-foreground"><ClipboardCheck className="mr-2 inline h-4 w-4" />Tooth chart entry is currently text-to-structured-data; a visual interactive odontogram is a separate follow-up.</div>}
      <div className="flex justify-end"><button type="submit" disabled={saving || loading || !encounterId} className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2.5 text-sm font-semibold text-primary-foreground disabled:cursor-not-allowed disabled:opacity-50">{saving ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}{saving ? 'Saving…' : 'Save assessment'}</button></div>
    </form>
  </div>;
}
