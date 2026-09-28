import { FormEvent, useMemo, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useClinicalReferences, type ClinicalReference } from '@/lib/clinicalReferences';

type PatientOption = { id: string; first_name: string; last_name: string; patient_code?: string | null };

type Props = {
  patients?: PatientOption[];
  patientId?: string | null;
  onSaved: () => void;
  onCancel?: () => void;
};

type FormState = {
  patientId: string;
  systolic: string;
  diastolic: string;
  heartRate: string;
  temperature: string;
  respiratoryRate: string;
  oxygenSaturation: string;
  weightKg: string;
  heightM: string;
  painScore: string;
  consciousness: string;
  complaint: string;
  notes: string;
};

const REFERENCE_PARAMETERS = [
  'blood_pressure_systolic',
  'blood_pressure_diastolic',
  'blood_pressure_combined',
  'body_temperature',
  'heart_rate',
  'respiratory_rate',
  'spo2',
  'pain_score',
  'weight_measurement',
  'height_measurement',
  'body_mass_index',
] as const;

const emptyForm: FormState = {
  patientId: '', systolic: '', diastolic: '', heartRate: '', temperature: '',
  respiratoryRate: '', oxygenSaturation: '', weightKg: '', heightM: '',
  painScore: '', consciousness: 'Alert', complaint: '', notes: '',
};

function numberOrNull(value: string) {
  return value.trim() === '' ? null : Number(value);
}

function ReferenceHelper({ reference, id, loading, error }: { reference?: ClinicalReference; id: string; loading?: boolean; error?: string | null }) {
  if (loading) return <span id={id} className="block text-xs text-muted-foreground">Loading clinical reference…</span>;
  if (!reference) {
    return <span id={id} className="block text-xs text-muted-foreground">{error ? 'Clinical reference could not be loaded; contact an administrator.' : 'No active clinical reference is configured for this field; contact an administrator.'}</span>;
  }
  return (
    <span id={id} className="block text-xs leading-5 text-muted-foreground">
      {reference.population_scope === 'adult' ? 'Adult reference. ' : ''}{reference.display_text}{' '}
      <span className="whitespace-normal">
        Source: <a href={reference.source_url} target="_blank" rel="noreferrer" className="underline underline-offset-2">{reference.source_name}</a>.
      </span>
    </span>
  );
}

export default function TriageRecordForm({ patients = [], patientId, onSaved, onCancel }: Props) {
  const { user } = useAuth();
  const [form, setForm] = useState<FormState>({ ...emptyForm, patientId: patientId ?? '' });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const { byParameter, loading: referencesLoading, error: referencesError } = useClinicalReferences([...REFERENCE_PARAMETERS]);

  const normalReference = (parameter: string) => byParameter.get(parameter);

  const alerts = useMemo(() => {
    const checks: Array<[keyof FormState, string]> = [
      ['systolic', 'blood_pressure_systolic'],
      ['diastolic', 'blood_pressure_diastolic'],
      ['heartRate', 'heart_rate'],
      ['temperature', 'body_temperature'],
      ['respiratoryRate', 'respiratory_rate'],
      ['oxygenSaturation', 'spo2'],
      ['painScore', 'pain_score'],
    ];
    return checks.flatMap(([key, parameter]) => {
      const reference = normalReference(parameter);
      const value = numberOrNull(form[key]);
      if (!reference || value === null || !Number.isFinite(value)) return [];
      if (reference.normal_max !== null && value > reference.normal_max) {
        return [`${parameter} ${value} is above the sourced upper reference limit of ${reference.normal_max}.`];
      }
      if (reference.normal_min !== null && value < reference.normal_min) {
        return [`${parameter} ${value} is below the sourced lower reference limit of ${reference.normal_min}.`];
      }
      return [];
    });
  }, [form, byParameter]);

  const bmi = useMemo(() => {
    const weight = numberOrNull(form.weightKg);
    const height = numberOrNull(form.heightM);
    return weight && height && height > 0 ? Number((weight / (height * height)).toFixed(2)) : null;
  }, [form.weightKg, form.heightM]);

  const set = (key: keyof FormState, value: string) => {
    setForm((current) => ({ ...current, [key]: value }));
    setErrors((current) => ({ ...current, [key]: '' }));
  };

  const validate = () => {
    const next: Record<string, string> = {};
    if (!form.patientId.trim()) next.patientId = 'Select the patient for this triage record.';
    const measurements: Array<[keyof FormState, string]> = [
      ['systolic', 'Systolic BP'], ['diastolic', 'Diastolic BP'], ['heartRate', 'Heart rate'],
      ['temperature', 'Temperature'], ['respiratoryRate', 'Respiratory rate'], ['oxygenSaturation', 'SpO₂'],
      ['weightKg', 'Weight'], ['heightM', 'Height'],
    ];
    measurements.forEach(([key, label]) => {
      const raw = form[key].trim();
      if (!raw) return;
      const value = Number(raw);
      if (!Number.isFinite(value) || value < 0) next[key] = label + ' must be a valid non-negative measurement.';
    });
    const hasCoreMeasurement = ['systolic','diastolic','temperature','oxygenSaturation','heartRate','respiratoryRate','weightKg','heightM'].some((key) => form[key as keyof FormState].trim() !== '');
    if (!hasCoreMeasurement) next.measurement = 'Enter at least one measured vital sign.';
    if (form.painScore) {
      const pain = Number(form.painScore);
      const reference = normalReference('pain_score');
      if (!Number.isFinite(pain) || pain < 0 || (reference?.normal_max !== null && reference?.normal_max !== undefined && pain > reference.normal_max)) {
        next.painScore = reference?.normal_max !== null && reference?.normal_max !== undefined
          ? 'Pain score must follow the sourced ' + (reference.normal_min ?? 0) + '–' + reference.normal_max + ' scale.'
          : 'Enter a valid pain score.';
      }
    }
    if (form.weightKg && Number(form.weightKg) <= 0) next.weightKg = 'Enter a measured weight greater than 0.';
    if (form.heightM && Number(form.heightM) <= 0) next.heightM = 'Enter a measured height in metres.';
    setErrors(next);
    return Object.keys(next).length === 0;
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!user?.id || !validate()) return;
    setSaving(true);
    try {
      const sbp = numberOrNull(form.systolic);
      const temp = numberOrNull(form.temperature);
      const spo2 = numberOrNull(form.oxygenSaturation);
      const hr = numberOrNull(form.heartRate);
      const critical = (temp !== null && temp >= 39) || (spo2 !== null && spo2 <= 92) || (hr !== null && hr >= 120) || (sbp !== null && sbp >= 180);
      const urgent = !critical && ((temp !== null && temp >= 38) || (spo2 !== null && spo2 <= 94) || (hr !== null && hr >= 100) || (sbp !== null && sbp >= 160));
      const values = {
        _patient_id: form.patientId,
        _systolic: sbp,
        _diastolic: numberOrNull(form.diastolic),
        _heart_rate: hr,
        _temperature: temp,
        _respiratory_rate: numberOrNull(form.respiratoryRate),
        _oxygen_saturation: spo2,
        _weight_kg: numberOrNull(form.weightKg),
        _height_m: numberOrNull(form.heightM),
        _pain_score: form.painScore ? Number(form.painScore) : null,
        _consciousness: form.consciousness || null,
        _presenting_complaint: form.complaint.trim() || null,
        _clinical_notes: form.notes.trim() || null,
        _priority: critical ? 'critical' : urgent ? 'urgent' : 'routine',
        _is_critical: critical,
      };
      const { error } = await (supabase as any).rpc('record_triage_assessment', values);
      if (error) throw error;
      toast.success('Triage record saved successfully.');
      setForm({ ...emptyForm, patientId: patientId ?? '' });
      setErrors({});
      onSaved();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Unable to save triage record.');
    } finally {
      setSaving(false);
    }
  };

  const input = (key: keyof FormState, label: string, placeholder: string, parameter?: string, options?: { step?: string; type?: string }) => {
    const helperId = `clinical-reference-${key}`;
    const reference = parameter ? normalReference(parameter) : undefined;
    return (
      <label className="space-y-1 text-sm">
        <span className="font-medium">{label}</span>
        <input
          aria-label={label}
          {...(parameter ? { 'aria-describedby': helperId } : {})}
          type={options?.type ?? 'number'}
          step={options?.step ?? 'any'}
          value={form[key]}
          onChange={(event) => set(key, event.target.value)}
          placeholder={placeholder}
          className={`input-medical w-full ${errors[key] ? 'border-destructive' : ''}`}
        />
        {parameter && (referencesLoading && !reference
          ? <span id={helperId} className="block text-xs text-muted-foreground">Loading clinical reference…</span>
          : <ReferenceHelper reference={reference} id={helperId} error={referencesError} />)}
        {errors[key] && <span className="text-xs text-destructive">{errors[key]}</span>}
      </label>
    );
  };

  return (
    <form onSubmit={submit} noValidate className="space-y-5">
      {!patientId && <label className="space-y-1 text-sm">
        <span className="font-medium">Patient</span>
        <select aria-label="Patient" value={form.patientId} onChange={(event) => set('patientId', event.target.value)} className={`input-medical w-full ${errors.patientId ? 'border-destructive' : ''}`}>
          <option value="">Select patient…</option>
          {patients.map((patient) => <option key={patient.id} value={patient.id}>{patient.first_name} {patient.last_name}{patient.patient_code ? ` · ${patient.patient_code}` : ''}</option>)}
        </select>
        {errors.patientId && <span className="text-xs text-destructive">{errors.patientId}</span>}
      </label>}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {input('systolic', 'Systolic BP', 'Enter systolic blood pressure', 'blood_pressure_systolic', { step: '1' })}
        {input('diastolic', 'Diastolic BP', 'Enter diastolic blood pressure', 'blood_pressure_diastolic', { step: '1' })}
        <div className="sm:col-span-2 lg:col-span-3 rounded-xl border border-muted bg-muted/20 p-3 text-xs text-muted-foreground">
          <span className="font-medium text-foreground">Combined BP reference: </span>{normalReference('blood_pressure_combined')?.display_text ?? (referencesLoading ? 'Loading clinical reference…' : 'No active combined BP reference is configured; contact an administrator.')}
          {normalReference('blood_pressure_combined') && <> <span>Source: </span><a href={normalReference('blood_pressure_combined')!.source_url} target="_blank" rel="noreferrer" className="underline">{normalReference('blood_pressure_combined')!.source_name}</a>.</>}
        </div>
        {input('heartRate', 'Heart rate', 'Enter pulse rate', 'heart_rate', { step: '1' })}
        {input('temperature', 'Temperature °C', 'Enter measured temperature', 'body_temperature', { step: '0.1' })}
        {input('respiratoryRate', 'Respiratory rate', 'Enter breaths per minute', 'respiratory_rate', { step: '1' })}
        {input('oxygenSaturation', 'SpO₂ %', 'Enter oxygen saturation', 'spo2', { step: '0.1' })}
        {input('weightKg', 'Weight (kg)', 'Enter measured weight', 'weight_measurement', { step: '0.1' })}
        {input('heightM', 'Height (m)', 'Enter measured height', 'height_measurement', { step: '0.01' })}
        {input('painScore', 'Pain score (0–10)', 'Enter pain score', 'pain_score', { step: '1' })}
      </div>

      {alerts.length > 0 && <div className="rounded-xl border-2 border-critical/60 bg-critical/10 p-4" role="alert"><p className="font-semibold text-critical">Reference-range attention</p><ul className="mt-1 list-disc pl-5 text-sm">{alerts.map((alert) => <li key={alert}>{alert}</li>)}</ul><p className="mt-2 text-xs text-muted-foreground">Recheck the measurement and follow the facility escalation protocol.</p></div>}

      {errors.measurement && <p className="text-sm text-destructive" role="alert">{errors.measurement}</p>}

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="space-y-1 text-sm">
          <span className="font-medium">Level of consciousness</span>
          <select aria-label="Level of consciousness" value={form.consciousness} onChange={(event) => set('consciousness', event.target.value)} className="input-medical w-full">
            <option>Alert</option><option>Confused</option><option>Drowsy</option><option>Unresponsive</option>
          </select>
        </label>
        <div className="rounded-xl border border-primary/20 bg-primary/5 p-3 text-sm">
          <span className="text-muted-foreground">Calculated BMI</span>
          <strong className="block text-xl">{bmi ?? '—'}</strong>
          <span className="text-xs text-muted-foreground">{bmi ? 'kg/m² · calculated from measured height and weight' : 'Enter weight and height to calculate BMI'}</span>
          {normalReference('body_mass_index') && <span className="mt-1 block text-xs text-muted-foreground">{normalReference('body_mass_index')!.display_text} Source: <a href={normalReference('body_mass_index')!.source_url} target="_blank" rel="noreferrer" className="underline">{normalReference('body_mass_index')!.source_name}</a>.</span>}
        </div>
      </div>

      <label className="space-y-1 text-sm">
        <span className="font-medium">Presenting complaint</span>
        <input aria-label="Presenting complaint" value={form.complaint} onChange={(event) => set('complaint', event.target.value)} placeholder="e.g. Fever and headache for two days" className="input-medical w-full" />
      </label>
      <label className="space-y-1 text-sm">
        <span className="font-medium">Clinical notes <span className="font-normal text-muted-foreground">(optional)</span></span>
        <textarea aria-label="Clinical notes" value={form.notes} onChange={(event) => set('notes', event.target.value)} placeholder="Add relevant observations or context; this is hidden from the triage summary by default." rows={3} className="input-medical w-full" />
      </label>

      <div className="flex justify-end gap-2">
        {onCancel && <button type="button" onClick={onCancel} className="btn-secondary">Cancel</button>}
        <button type="submit" disabled={saving} className="btn-primary">{saving ? 'Saving…' : 'Save triage record'}</button>
      </div>
    </form>
  );
}
