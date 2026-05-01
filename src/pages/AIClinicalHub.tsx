import { useState } from 'react';
import { Cpu, Activity, ShieldCheck, Sparkles, BrainCircuit } from 'lucide-react';

const specialists = [
  { id: 'physician', title: 'AI Physician', score: 87, description: 'Analyzes symptoms and history for diagnostic probabilities.' },
  { id: 'radiologist', title: 'AI Radiologist', score: 82, description: 'Interprets imaging and recommends additional studies.' },
  { id: 'ophthalmologist', title: 'AI Ophthalmologist', score: 78, description: 'Detects eye disease risks from exam data.' },
  { id: 'pharmacist', title: 'AI Pharmacist', score: 91, description: 'Validates prescriptions and identifies drug interactions.' },
];

export default function AIClinicalHub() {
  const [selected, setSelected] = useState('physician');

  const active = specialists.find((item) => item.id === selected);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">AI Clinical Decision System</h1>
          <p className="text-muted-foreground">Clinical AI specialists analyze symptoms, labs, imaging and vital signs.</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <Cpu className="w-4 h-4" /> Analyze Case
        </button>
      </div>

      <div className="grid gap-6 lg:grid-cols-[280px_1fr]">
        <div className="card-medical p-6 space-y-4">
          <div className="flex items-center gap-3">
            <BrainCircuit className="w-5 h-5 text-primary" />
            <div>
              <h2 className="text-lg font-semibold">AI Specialists</h2>
              <p className="text-sm text-muted-foreground">Select a specialist to review case recommendations.</p>
            </div>
          </div>
          <div className="space-y-3">
            {specialists.map((specialist) => (
              <button
                key={specialist.id}
                onClick={() => setSelected(specialist.id)}
                className={`w-full rounded-2xl border p-4 text-left transition ${selected === specialist.id ? 'border-primary bg-primary/10' : 'border-border hover:border-primary hover:bg-muted'}`}
              >
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="font-medium">{specialist.title}</p>
                    <p className="text-sm text-muted-foreground">{specialist.description}</p>
                  </div>
                  <span className="font-semibold text-primary">{specialist.score}%</span>
                </div>
              </button>
            ))}
          </div>
        </div>

        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Specialist Overview</h2>
              <p className="text-sm text-muted-foreground">Detailed recommendations and risk scores.</p>
            </div>
            <Sparkles className="w-5 h-5 text-success" />
          </div>

          {active ? (
            <div className="space-y-4">
              <div className="rounded-2xl border border-border p-4">
                <p className="text-sm text-muted-foreground">Current specialist</p>
                <p className="mt-2 text-xl font-semibold">{active.title}</p>
              </div>
              <div className="rounded-2xl border border-border p-4 bg-background/60">
                <p className="font-medium">Diagnostic Probability</p>
                <p className="text-3xl mt-2 font-semibold text-primary">{active.score}%</p>
              </div>
              <div className="rounded-2xl border border-border p-4">
                <p className="text-sm text-muted-foreground">Recommendation</p>
                <p className="mt-2">{active.description} The model suggests next steps based on vital sign patterns, lab results and previous encounters.</p>
              </div>
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">Select an AI specialist on the left to view details.</p>
          )}
        </div>
      </div>
    </div>
  );
}
