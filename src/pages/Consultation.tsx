import { useMemo, useState } from 'react';
import { ArrowRight, ClipboardList, Stethoscope, Plus, Sparkles, BookOpen, CheckCircle, ShieldCheck } from 'lucide-react';
import { addDiagnosisToConsultation, completeConsultation, createConsultationEncounter } from '@/lib/healthApi';
import MedicalTermInput from '@/components/MedicalTermInput';

const patientProfile = {
  id: 'P-0004',
  patientId: 'P-0004',
  firstName: 'Nana',
  lastName: 'Baah',
  bloodGroup: 'B+',
  genotype: 'AS',
  allergies: ['Penicillin'],
  chronicConditions: ['Hypertension'],
  lastConsultations: [
    { date: '2026-04-20', practitioner: 'Dr. Sarah Johnson', summary: 'Review hypertension management', outcome: 'Medication adjusted' },
    { date: '2026-03-14', practitioner: 'Dr. Michael Chen', summary: 'Chest pain assessment', outcome: 'EKG ordered' },
    { date: '2026-02-10', practitioner: 'Dr. Emily Davis', summary: 'Diabetes follow-up', outcome: 'Diet review' },
  ],
};

const aiSuggestions = [
  { title: 'AI Physician', description: 'Suggests possible hypertensive emergency with urgent follow-up.' },
  { title: 'AI Pharmacist', description: 'Checks drug interactions for current antihypertensive therapy.' },
  { title: 'AI Cardiologist', description: 'Recommends ECG review and blood pressure stabilization.' },
];

export default function Consultation() {
  const [symptoms, setSymptoms] = useState<string[]>(['Headache', 'Dizziness']);
  const [newSymptom, setNewSymptom] = useState('');
  const [diagnoses, setDiagnoses] = useState<string[]>(['Hypertensive urgency']);
  const [newDiagnosis, setNewDiagnosis] = useState('');
  const [principalDiagnosis, setPrincipalDiagnosis] = useState('Hypertensive urgency');
  const [notes, setNotes] = useState('Patient reports intermittent chest tightness and headaches over 3 days.');
  const [message, setMessage] = useState('');

  const handleAddSymptom = () => {
    if (!newSymptom.trim()) return;
    setSymptoms((prev) => [...prev, newSymptom.trim()]);
    setNewSymptom('');
  };

  const handleAddDiagnosis = () => {
    if (!newDiagnosis.trim()) return;
    const entry = newDiagnosis.trim();
    setDiagnoses((prev) => [...prev, entry]);
    addDiagnosisToConsultation(entry);
    setNewDiagnosis('');
  };

  const canComplete = Boolean(principalDiagnosis);

  const handleComplete = async () => {
    if (!canComplete) {
      setMessage('A principal diagnosis must be selected before completion.');
      return;
    }

    await completeConsultation({ encounterId: 'enc-001', principalDiagnosis });
    createConsultationEncounter({ patientId: patientProfile.patientId, symptoms, diagnoses, principalDiagnosis, notes });
    setMessage('Consultation completed successfully with principal diagnosis set.');
  };

  const latestDiagnosis = useMemo(() => diagnoses[diagnoses.length - 1], [diagnoses]);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Consultation Clerking</h1>
          <p className="text-muted-foreground">Complete the encounter without switching screens.</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <ArrowRight className="w-4 h-4" /> Submit Consultation
        </button>
      </div>

      <div className="grid gap-6 xl:grid-cols-[320px_1fr]">
        <div className="card-medical p-6 space-y-4">
          <div>
            <h2 className="text-lg font-semibold">Patient Details</h2>
            <p className="text-sm text-muted-foreground">{patientProfile.firstName} {patientProfile.lastName}</p>
          </div>
          <div className="grid gap-3">
            <div className="rounded-2xl border border-border p-4">
              <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Blood Group</p>
              <p className="mt-2 font-semibold">{patientProfile.bloodGroup}</p>
            </div>
            <div className="rounded-2xl border border-border p-4">
              <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Genotype</p>
              <p className="mt-2 font-semibold">{patientProfile.genotype}</p>
            </div>
            <div className="rounded-2xl border border-border p-4">
              <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Allergies</p>
              <p className="mt-2 font-semibold">{patientProfile.allergies.join(', ')}</p>
            </div>
            <div className="rounded-2xl border border-border p-4">
              <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Chronic Conditions</p>
              <p className="mt-2 font-semibold">{patientProfile.chronicConditions.join(', ')}</p>
            </div>
          </div>

          <div className="space-y-3">
            <h3 className="text-base font-semibold">Recent Consultations</h3>
            {patientProfile.lastConsultations.map((consult) => (
              <div key={consult.date} className="rounded-2xl border border-border p-4">
                <p className="text-sm font-medium">{consult.date} · {consult.practitioner}</p>
                <p className="text-sm text-muted-foreground mt-1">{consult.summary}</p>
                <p className="text-xs text-muted-foreground mt-2">Outcome: {consult.outcome}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="space-y-6">
          <div className="card-medical p-6">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h2 className="text-lg font-semibold">Clerking Interface</h2>
                <p className="text-sm text-muted-foreground">Capture symptoms, provisional diagnoses and principal diagnosis.</p>
              </div>
              <ShieldCheck className="w-5 h-5 text-success" />
            </div>

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium mb-2">Symptoms</label>
                <div className="flex items-center gap-3 mb-3">
                  <input
                    value={newSymptom}
                    onChange={(e) => setNewSymptom(e.target.value)}
                    placeholder="Add a new symptom"
                    className="input-medical flex-1"
                  />
                  <button type="button" onClick={handleAddSymptom} className="btn-secondary inline-flex items-center gap-2">
                    <Plus className="w-4 h-4" /> Add
                  </button>
                </div>
                <div className="space-y-2">
                  {symptoms.map((symptom, index) => (
                    <div key={index} className="rounded-2xl border border-border p-3 text-sm">{symptom}</div>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium mb-2">Provisional Diagnoses</label>
                <div className="flex items-center gap-3 mb-3">
                    <MedicalTermInput
                    value={newDiagnosis}
                    onChange={setNewDiagnosis}
                    placeholder="Add a provisional diagnosis"
                    className="input-medical flex-1"
                      diagnosisOnly
                  />
                  <button type="button" onClick={handleAddDiagnosis} className="btn-secondary inline-flex items-center gap-2">
                    <Plus className="w-4 h-4" /> Add
                  </button>
                </div>
                <div className="grid gap-2">
                  {diagnoses.map((diagnosis, index) => (
                    <div key={`${diagnosis}-${index}`} className="rounded-2xl border border-border p-3 flex items-center justify-between">
                      <span>{diagnosis}</span>
                      <button
                        type="button"
                        onClick={() => setPrincipalDiagnosis(diagnosis)}
                        className={diagnosis === principalDiagnosis ? 'text-success font-semibold' : 'text-muted-foreground text-xs'}
                      >
                        {diagnosis === principalDiagnosis ? 'Principal' : 'Set as Principal'}
                      </button>
                    </div>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium mb-2">Clerking Notes</label>
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  rows={5}
                  className="textarea-medical w-full"
                />
              </div>

              <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div className="text-sm text-muted-foreground">
                  Principal Diagnosis is required before completion.
                </div>
                <button
                  type="button"
                  onClick={handleComplete}
                  className="btn-primary"
                >
                  Complete Consultation
                </button>
              </div>
              {message && <p className="text-sm text-success">{message}</p>}
            </div>
          </div>

          <div className="card-medical p-6">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h2 className="text-lg font-semibold">AI Decision Support</h2>
                <p className="text-sm text-muted-foreground">Guidance from clinical AI specialists.</p>
              </div>
              <Sparkles className="w-5 h-5 text-primary" />
            </div>
            <div className="space-y-3">
              {aiSuggestions.map((item) => (
                <div key={item.title} className="rounded-2xl border border-border p-4">
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <p className="font-medium">{item.title}</p>
                      <p className="text-sm text-muted-foreground mt-1">{item.description}</p>
                    </div>
                    <CheckCircle className="w-5 h-5 text-success" />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
