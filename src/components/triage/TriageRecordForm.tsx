import { FormEvent, useMemo, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

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

const emptyForm: FormState = {
  patientId: '', systolic: '', diastolic: '', heartRate: '', temperature: '',
  respiratoryRate: '', oxygenSaturation: '', weightKg: '', heightM: '',
  painScore: '', consciousness: 'Alert', complaint: '', notes: '',
};

function numberOrNull(value: string) {
  return value.trim() === '' ? null : Number(value);
}

export default function TriageRecordForm({ patients = [], patientId, onSaved, onCancel }: Props) {
  const { user } = useAuth();
  const [form, setForm] = useState<FormState>({ ...emptyForm, patientId: patientId ?? '' });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);

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
    const required: Array<[keyof FormState, string, number, number]> = [
      ['systolic', 'Systolic BP', 1, 399],
      ['diastolic', 'Diastolic BP', 1, 299],
      ['heartRate', 'Heart rate', 1, 299],
      ['temperature', 'Temperature', 20.1, 49.9],
      ['respiratoryRate', 'Respiratory rate', 1, 99],
      ['oxygenSaturation', 'SpO₂', 0, 100],
    ];
    required.forEach(([key, label, min, max]) => {
      const value = numberOrNull(form[key]);
      if (value === null || !Number.isFinite(value)) next[key] = `${label} is required.`;
      else if (value < min || value > max) next[key] = `${label} must be between ${min} and ${max}.`;
    });
    if (form.painScore && (Number(form.painScore) < 0 || Number(form.painScore) > 10)) next.painScore = 'Pain score must be 0–10.';
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
      const values = {
        _patient_id: form.patientId,
        _systolic: Number(form.systolic),
        _diastolic: Number(form.diastolic),
        _heart_rate: Number(form.heartRate),
        _temperature: Number(form.temperature),
        _respiratory_rate: Number(form.respiratoryRate),
        _oxygen_saturation: Number(form.oxygenSaturation),
        _weight_kg: numberOrNull(form.weightKg),
        _height_m: numberOrNull(form.heightM),
        _pain_score: form.painScore ? Number(form.painScore) : null,
        _consciousness: form.consciousness || null,
        _presenting_complaint: form.complaint.trim() || null,
        _clinical_notes: form.notes.trim() || null,
        _priority: 'routine',
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

  const input = (key: keyof FormState, label: string, placeholder: string, options?: { step?: string; type?: string }) => (
    <label className="space-y-1 text-sm">
      <span className="font-medium">{label}</span>
      <input
        aria-label={label}
        type={options?.type ?? 'number'}
        step={options?.step ?? 'any'}
        value={form[key]}
        onChange={(event) => set(key, event.target.value)}
        placeholder={placeholder}
        className={`input-medical w-full ${errors[key] ? 'border-destructive' : ''}`}
      />
      {errors[key] && <span className="text-xs text-destructive">{errors[key]}</span>}
    </label>
  );

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
        {input('systolic', 'Systolic BP', 'e.g. 120 mmHg', { step: '1' })}
        {input('diastolic', 'Diastolic BP', 'e.g. 80 mmHg', { step: '1' })}
        {input('heartRate', 'Heart rate', 'e.g. 72 bpm', { step: '1' })}
        {input('temperature', 'Temperature °C', 'e.g. 36.8 °C', { step: '0.1' })}
        {input('respiratoryRate', 'Respiratory rate', 'e.g. 16 /min', { step: '1' })}
        {input('oxygenSaturation', 'SpO₂ %', 'e.g. 98%', { step: '0.1' })}
        {input('weightKg', 'Weight (kg)', 'e.g. 70.5 kg', { step: '0.1' })}
        {input('heightM', 'Height (m)', 'e.g. 1.75 m', { step: '0.01' })}
        {input('painScore', 'Pain score (0–10)', 'e.g. 3', { step: '1' })}
      </div>

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
