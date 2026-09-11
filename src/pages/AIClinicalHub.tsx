import { useState } from 'react';
import { BrainCircuit, Cpu, ShieldCheck, Sparkles } from 'lucide-react';

const specialists = [
  { id: 'physician', title: 'AI Physician', description: 'Structured clinical reasoning support from symptoms, history, vitals and documented investigations.' },
  { id: 'surgeon', title: 'AI Surgeon', description: 'Surgical decision-support workspace for procedure planning, risk prompts and peri-operative considerations.' },
  { id: 'neurosurgeon', title: 'AI Neurosurgeon', description: 'Neurosurgical decision-support and visualization workspace for neurological cases and imaging review.' },
  { id: 'radiologist', title: 'AI Radiologist', description: 'Imaging review support and structured prompts for radiology findings.' },
  { id: 'ophthalmologist', title: 'AI Ophthalmologist', description: 'Ophthalmic examination and differential-support workspace.' },
  { id: 'pharmacist', title: 'AI Pharmacist', description: 'Medication and prescription review support, including interaction and safety prompts.' },
  { id: 'nurse', title: 'AI Specialist Nurse', description: 'Nursing workflow support for observations, care plans, escalation and monitoring.' },
];

export default function AIClinicalHub() {
  const [selected, setSelected] = useState('physician');
  const active = specialists.find(item => item.id === selected);
  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold">AI Clinical Decision Support</h1><p className="text-muted-foreground">Specialist workspaces for clinician-reviewed decision support. No fabricated scores or autonomous diagnoses are presented.</p></div><button className="btn-primary inline-flex items-center gap-2"><Cpu className="w-4 h-4" /> Prepare case</button></div>
    <div className="rounded-2xl border border-warning/20 bg-warning/5 p-4 text-sm flex gap-3"><ShieldCheck className="w-5 h-5 text-warning shrink-0" /><p>AI output is advisory only. It must be based on actual patient data and reviewed by an appropriately qualified clinician before any diagnosis, procedure, medication or treatment decision.</p></div>
    <div className="grid gap-6 lg:grid-cols-[320px_1fr]">
      <div className="card-medical p-5 space-y-3"><div className="flex items-center gap-3 mb-4"><BrainCircuit className="w-5 h-5 text-primary" /><div><h2 className="font-semibold">Specialists</h2><p className="text-xs text-muted-foreground">Select a decision-support domain.</p></div></div>{specialists.map(s => <button key={s.id} onClick={() => setSelected(s.id)} className={`w-full rounded-2xl border p-4 text-left transition ${selected === s.id ? 'border-primary bg-primary/10' : 'border-border hover:border-primary hover:bg-muted'}`}><p className="font-medium">{s.title}</p><p className="text-xs text-muted-foreground mt-1">{s.description}</p></button>)}</div>
      <div className="card-medical p-6"><div className="flex items-center justify-between mb-5"><div><h2 className="text-lg font-semibold">{active?.title}</h2><p className="text-sm text-muted-foreground">Clinical decision-support workspace</p></div><Sparkles className="w-5 h-5 text-primary" /></div><div className="grid gap-4 md:grid-cols-2"><div className="rounded-2xl border border-border p-5"><p className="font-medium">Case data</p><p className="text-sm text-muted-foreground mt-2">Connect the selected patient, encounters, vitals, laboratory results and imaging before requesting analysis.</p><button className="btn-ghost mt-4 text-xs">Select patient</button></div><div className="rounded-2xl border border-border p-5"><p className="font-medium">Output</p><p className="text-sm text-muted-foreground mt-2">No analysis has been generated. This prevents the interface from presenting placeholder probabilities as clinical findings.</p><button className="btn-primary mt-4 text-xs">Analyze documented case</button></div></div><div className="mt-5 rounded-2xl border border-border p-5"><p className="font-medium">Specialist scope</p><p className="text-sm text-muted-foreground mt-2">{active?.description}</p><p className="text-xs text-muted-foreground mt-4">Any future AI response must include provenance, model status and clinician-review state before it becomes part of the medical record.</p></div></div>
    </div>
  </div>;
}
