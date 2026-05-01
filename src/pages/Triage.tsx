import { useMemo, useState } from 'react';
import { ArrowRight, Activity, HeartPulse, Thermometer, Droplet, Pulse, Weight, Scale, ShieldCheck, AlertTriangle, ListChecks } from 'lucide-react';
import { evaluateTriagePriority } from '@/lib/healthApi';
import { VitalSigns } from '@/types';

const defaultPatient = {
  id: 'P-0001',
  patientId: 'P-0001',
  firstName: 'Emmanuel',
  lastName: 'Owusu',
  dateOfBirth: '1988-06-14',
  gender: 'male' as const,
  email: 'emmanuel.owusu@example.com',
  phone: '+233 24 123 4567',
  address: 'Accra Ridge',
  emergencyContact: { name: 'Amina Owusu', relationship: 'Spouse', phone: '+233 24 765 4321' },
  registrationDate: '2026-04-27',
  status: 'active' as const,
};

const defaultWaitingList = [
  { id: 'P-0010', name: 'Raymond Boateng', triage: 'Urgent' },
  { id: 'P-0011', name: 'Esther Mensah', triage: 'Moderate' },
  { id: 'P-0012', name: 'Grace Nyamekye', triage: 'Routine' },
];

export default function Triage() {
  const [vitals, setVitals] = useState<VitalSigns>({
    id: 'v-01',
    patientId: defaultPatient.patientId,
    recordedBy: 'Nurse Emily',
    recordedAt: new Date().toISOString(),
    bloodPressure: { systolic: 138, diastolic: 92 },
    heartRate: 110,
    temperature: 38.2,
    respiratoryRate: 24,
    oxygenSaturation: 91,
    weight: 78,
    height: 1.72,
    notes: 'Patient reports chest discomfort and dizziness.',
    isCritical: false,
  });
  const [evaluation, setEvaluation] = useState('Routine');

  const bmi = useMemo(() => {
    if (!vitals.weight || !vitals.height) return 0;
    return Number((vitals.weight / (vitals.height * vitals.height)).toFixed(1));
  }, [vitals.weight, vitals.height]);

  const updateVital = (field: string, value: string | number) => {
    setVitals((prev) => ({
      ...prev,
      [field]: typeof value === 'string' && field !== 'recordedAt' ? Number(value) : value,
    } as VitalSigns));
  };

  const handleEvaluate = () => {
    const priority = evaluateTriagePriority(vitals);
    setEvaluation(priority);
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Triage & Vital Signs</h1>
          <p className="text-muted-foreground">Record urgency and AI-assisted priority categorization.</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <ArrowRight className="w-4 h-4" /> Start New Triage
        </button>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="card-medical p-6">
          <h2 className="text-lg font-semibold mb-4">Patient Summary</h2>
          <div className="space-y-3 text-sm text-muted-foreground">
            <p><span className="font-medium text-foreground">Name:</span> {defaultPatient.firstName} {defaultPatient.lastName}</p>
            <p><span className="font-medium text-foreground">Patient ID:</span> {defaultPatient.patientId}</p>
            <p><span className="font-medium text-foreground">DOB:</span> {defaultPatient.dateOfBirth}</p>
            <p><span className="font-medium text-foreground">Phone:</span> {defaultPatient.phone}</p>
            <p><span className="font-medium text-foreground">Emergency Contact:</span> {defaultPatient.emergencyContact.name} ({defaultPatient.emergencyContact.relationship})</p>
          </div>
          <div className="mt-6 grid grid-cols-2 gap-3">
            <div className="rounded-2xl border border-border p-4">
              <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Current Priority</p>
              <p className="mt-2 text-2xl font-semibold">{evaluation}</p>
            </div>
            <div className="rounded-2xl border border-border p-4">
              <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">AI Risk</p>
              <p className="mt-2 text-2xl font-semibold text-warning">{evaluation === 'Critical' ? 'High' : 'Medium'}</p>
            </div>
          </div>
        </div>

        <div className="lg:col-span-2 card-medical p-6">
          <h2 className="text-lg font-semibold mb-4">Vital Signs</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="rounded-2xl border border-border p-4 space-y-3">
              <div className="flex items-center gap-3 text-muted-foreground"><HeartPulse className="w-4 h-4" /> Heart Rate</div>
              <input type="number" value={vitals.heartRate} onChange={(e) => updateVital('heartRate', e.target.value)} className="input-medical" />
            </div>
            <div className="rounded-2xl border border-border p-4 space-y-3">
              <div className="flex items-center gap-3 text-muted-foreground"><Thermometer className="w-4 h-4" /> Temperature (°C)</div>
              <input type="number" step="0.1" value={vitals.temperature} onChange={(e) => updateVital('temperature', e.target.value)} className="input-medical" />
            </div>
            <div className="rounded-2xl border border-border p-4 space-y-3">
              <div className="flex items-center gap-3 text-muted-foreground"><Activity className="w-4 h-4" /> Respiratory Rate</div>
              <input type="number" value={vitals.respiratoryRate} onChange={(e) => updateVital('respiratoryRate', e.target.value)} className="input-medical" />
            </div>
            <div className="rounded-2xl border border-border p-4 space-y-3">
              <div className="flex items-center gap-3 text-muted-foreground"><Droplet className="w-4 h-4" /> Oxygen Saturation</div>
              <input type="number" value={vitals.oxygenSaturation} onChange={(e) => updateVital('oxygenSaturation', e.target.value)} className="input-medical" />
            </div>
            <div className="rounded-2xl border border-border p-4 space-y-3">
              <div className="flex items-center gap-3 text-muted-foreground"><Scale className="w-4 h-4" /> Height (m)</div>
              <input type="number" step="0.01" value={vitals.height ?? ''} onChange={(e) => updateVital('height', e.target.value)} className="input-medical" />
            </div>
            <div className="rounded-2xl border border-border p-4 space-y-3">
              <div className="flex items-center gap-3 text-muted-foreground"><Weight className="w-4 h-4" /> Weight (kg)</div>
              <input type="number" step="0.1" value={vitals.weight ?? ''} onChange={(e) => updateVital('weight', e.target.value)} className="input-medical" />
            </div>
          </div>

          <div className="mt-6 flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-sm text-muted-foreground">BMI</p>
              <p className="text-3xl font-semibold">{bmi || '--'}</p>
            </div>
            <button onClick={handleEvaluate} className="btn-primary">Run AI Evaluation</button>
          </div>
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Waiting List</h2>
              <p className="text-sm text-muted-foreground">Live triage queue from the emergency desk.</p>
            </div>
            <ListChecks className="w-5 h-5 text-primary" />
          </div>
          <div className="space-y-3">
            {defaultWaitingList.map((item) => (
              <div key={item.id} className="rounded-2xl border border-border p-4 flex items-center justify-between">
                <div>
                  <p className="font-medium">{item.name}</p>
                  <p className="text-xs text-muted-foreground">{item.id}</p>
                </div>
                <span className="badge-status badge-warning">{item.triage}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Critical Patients</h2>
              <p className="text-sm text-muted-foreground">Patients requiring immediate intervention.</p>
            </div>
            <AlertTriangle className="w-5 h-5 text-critical" />
          </div>
          <div className="space-y-3">
            <div className="rounded-2xl border border-critical/20 bg-critical/5 p-4">
              <p className="font-medium">Kwame Asare</p>
              <p className="text-sm text-muted-foreground">BP 190/120 · SpO2 86% · AI: Critical</p>
            </div>
            <div className="rounded-2xl border border-warning/20 bg-warning/5 p-4">
              <p className="font-medium">Eunice Addo</p>
              <p className="text-sm text-muted-foreground">HR 124 · Temp 39.4°C · AI: Urgent</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
