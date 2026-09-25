import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  AlertTriangle,
  CheckCircle2,
  FileText,
  HeartPulse,
  History,
  Pill,
  Plus,
  ShieldAlert,
  Stethoscope,
  BedDouble,
  Trash2,
  X,
  Clock3,
  UserRound,
  Send,
  Save,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { toast } from "@/hooks/use-toast";
import MedicalTermInput from "@/components/MedicalTermInput";
import type { DiagnosisSuggestion } from "@/lib/medicalTerms";

interface Patient {
  id: string;
  first_name: string;
  last_name: string;
  patient_code: string;
}
interface Encounter {
  id: string;
  patient_id: string;
  symptoms: string | null;
  clerking_notes: string | null;
  principal_diagnosis: string | null;
  treatment_plan: string | null;
  status: string;
  admission_id: string | null;
  created_at: string;
  submitted_at?: string | null;
  version_no?: number | null;
}
interface Diagnosis {
  id: string;
  encounter_id: string;
  diagnosis: string;
  is_principal: boolean;
}
interface Prescription {
  id: string;
  medication: string;
  dosage: string | null;
  frequency: string | null;
  duration: string | null;
  status: string;
}
interface BMIContext {
  bmi: number | null;
  category: string;
  weight_kg: number | null;
  height_m: number | null;
  recorded_at: string | null;
}
interface ClinicalContext {
  patient?: {
    patient_code?: string;
    name?: string;
    blood_group?: string | null;
    genotype?: string | null;
    allergies?: string | null;
    chronic_conditions?: string | null;
  };
  previous_encounters?: Array<{
    id: string;
    created_at: string;
    status: string;
    principal_diagnosis: string | null;
    symptoms: string | null;
    treatment_plan: string | null;
    diagnoses: string[];
  }>;
  recent_vitals?: Array<{
    recorded_at: string;
    systolic: number | null;
    diastolic: number | null;
    pulse_rate: number | null;
    temperature: number | null;
    oxygen_saturation: number | null;
    priority: string | null;
  }>;
}
const db = supabase as any;

function BMIContextCard({ patientId }: { patientId: string }) {
  const [bmi, setBmi] = useState<BMIContext | null>(null);
  useEffect(() => {
    let active = true;
    const load = async () => {
      const { data, error } = await db.rpc("get_patient_bmi_context", {
        _patient_id: patientId,
      });
      if (!active) return;
      if (error) {
        toast({
          title: "BMI context unavailable",
          description: error.message,
          variant: "destructive",
        });
        return;
      }
      setBmi((data?.[0] ?? null) as BMIContext | null);
    };
    void load();
    return (
    <div className="space-y-6 animate-fade-in">
      <header className="rounded-3xl border border-border bg-card p-5 shadow-sm sm:p-7">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div><p className="mb-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">Patient Care · Encounter</p><h1 className="text-2xl font-heading font-bold tracking-tight">Encounter Workspace</h1><p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">Review historical encounters first, then open the selected document in a focused clinical workspace without leaving the encounter page.</p></div>
          <button type="button" onClick={() => setIsHistoryOpen(true)} className="btn-secondary inline-flex items-center gap-2"><History className="w-4 h-4" /> Encounter history</button>
        </div>
      </header>
      <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(300px,360px)]">
        <form onSubmit={createEncounter} className="card-medical p-5 space-y-4">
          <div className="flex items-start justify-between gap-3"><div><h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New encounter</h2><p className="mt-1 text-xs text-muted-foreground">Save creates a draft. Final submission happens only after the clinical document is complete.</p></div><span className="rounded-full border border-warning/40 bg-warning/5 px-2.5 py-1 text-[10px] font-semibold text-warning">Draft-first</span></div>
          <select value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full" required><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} ({p.patient_code})</option>)}</select>
          <div className="grid gap-3 md:grid-cols-2"><textarea value={symptoms} onChange={(e) => setSymptoms(e.target.value)} placeholder="Presenting symptoms / complaints" className="input-medical w-full" rows={4} /><textarea value={clerking} onChange={(e) => setClerking(e.target.value)} placeholder="Clerking / history notes" className="input-medical w-full" rows={4} /></div>
          <button type="submit" className="btn-primary inline-flex items-center gap-2"><Save className="w-4 h-4" /> Save draft</button>
        </form>
        <section className="card-medical p-5">
          <div className="flex items-center justify-between gap-3 mb-3"><div><h2 className="font-semibold flex items-center gap-2"><History className="w-4 h-4 text-primary" /> Recent encounters</h2><p className="text-xs text-muted-foreground mt-1">{encounters.length} recent records</p></div><button type="button" onClick={() => setIsHistoryOpen(true)} className="text-xs text-primary">View all</button></div>
          <div className="space-y-2 max-h-[320px] overflow-auto">{encounters.slice(0, 8).map((item) => { const p = patients.find((x) => x.id === item.patient_id); const active = selected?.id === item.id; return <button type="button" key={item.id} onClick={() => { setSelected(item); setIsHistoryOpen(false); }} className={`w-full rounded-xl border p-3 text-left transition-colors ${active ? 'border-primary bg-primary/5' : 'border-border hover:bg-accent/40'}`}><div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="font-medium text-sm truncate">{p ? `${p.first_name} ${p.last_name}` : 'Patient record'}</p><p className="text-xs text-muted-foreground">{p?.patient_code ?? item.patient_id} · {new Date(item.created_at).toLocaleDateString()}</p></div><span className="shrink-0 rounded-full bg-muted px-2 py-1 text-[10px] capitalize">{item.status}</span></div><p className="mt-2 text-xs text-muted-foreground truncate">{item.principal_diagnosis || item.symptoms || 'Clinical encounter'}</p></button>; })}</div>
        </section>
      </section>
      {isHistoryOpen && <div className="fixed inset-0 z-[70] bg-background/80 backdrop-blur-sm p-4 sm:p-8" role="dialog" aria-modal="true" aria-labelledby="encounter-history-title">
        <div className="mx-auto flex h-full max-w-5xl flex-col overflow-hidden rounded-3xl border border-border bg-card shadow-2xl">
          <div className="flex items-center justify-between gap-3 border-b border-border p-5"><div><h2 id="encounter-history-title" className="text-lg font-semibold">Patient encounter history</h2><p className="text-xs text-muted-foreground">Select an entire row to open the clinical document.</p></div><button type="button" onClick={() => setIsHistoryOpen(false)} className="btn-ghost" aria-label="Close encounter history"><X className="w-5 h-5" /></button></div>
          <div className="flex-1 overflow-auto p-4"><div className="overflow-hidden rounded-2xl border border-border">
            {encounters.map((item) => { const p = patients.find((x) => x.id === item.patient_id); const creator = item.practitioner_id === user?.id ? 'You' : 'Clinical staff'; return <button type="button" key={item.id} onClick={() => { setSelected(item); setIsHistoryOpen(false); }} className="grid w-full grid-cols-[minmax(0,1.6fr)_minmax(110px,0.8fr)_minmax(120px,0.9fr)_90px] gap-3 border-b border-border p-4 text-left last:border-b-0 hover:bg-muted/40 focus-visible:bg-muted/40"><div className="min-w-0"><p className="font-medium truncate">{p ? `${p.first_name} ${p.last_name}` : 'Patient record'}</p><p className="text-xs text-muted-foreground truncate">{p?.patient_code ?? item.patient_id}</p></div><div><p className="text-xs text-muted-foreground">Date</p><p className="text-sm">{new Date(item.created_at).toLocaleDateString()}</p><p className="text-[10px] text-muted-foreground">{encounterAge(item.created_at)}</p></div><div><p className="text-xs text-muted-foreground">Created by</p><p className="text-sm">{creator}</p><p className="text-[10px] text-muted-foreground">Version {item.version_no ?? 1}</p></div><div className="flex items-start justify-end"><span className="rounded-full bg-muted px-2 py-1 text-[10px] capitalize">{item.status}</span></div></button>; })}
            {!encounters.length && <div className="p-10 text-center text-sm text-muted-foreground">No historical encounters are available.</div>}
          </div></div>
        </div>
      </div>}
      {selected && <div className="fixed inset-0 z-[65] bg-slate-950/55 backdrop-blur-sm p-2 sm:p-4" role="dialog" aria-modal="true" aria-labelledby="active-encounter-title">
        <div className="mx-auto flex h-full max-w-7xl flex-col overflow-hidden rounded-3xl border border-border bg-background shadow-2xl">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border bg-card p-4 sm:p-5">
            <div className="min-w-0"><p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-primary">Active clinical document</p><h2 id="active-encounter-title" className="mt-1 text-lg font-semibold truncate">Encounter · {patients.find((p) => p.id === selected.patient_id)?.first_name ?? 'Patient'} {patients.find((p) => p.id === selected.patient_id)?.last_name ?? ''}</h2><p className="text-xs text-muted-foreground">{patients.find((p) => p.id === selected.patient_id)?.patient_code ?? selected.patient_id} · {new Date(selected.created_at).toLocaleString()} · {encounterAge(selected.created_at)}</p></div>
            <div className="flex flex-wrap items-center gap-2"><span className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold ${selected.status === 'completed' ? 'bg-success/10 text-success' : 'bg-warning/10 text-warning'}`}>{selected.status === 'completed' ? <CheckCircle2 className="w-3.5 h-3.5" /> : <Clock3 className="w-3.5 h-3.5" />}{selected.status === 'completed' ? 'Submitted' : 'Draft'}</span>{selected.status === 'completed' && !selected.admission_id && <button type="button" onClick={() => void admitEncounter()} disabled={admitting} className="btn-primary inline-flex items-center gap-2"><BedDouble className="w-4 h-4" />{admitting ? 'Admitting…' : 'Initiate admission'}</button>}{selected.admission_id && <span className="inline-flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/5 px-3 py-2 text-sm font-medium text-primary"><BedDouble className="w-4 h-4" /> Admission active</span>}{selected.status !== 'completed' && <button type="button" onClick={() => void completeEncounter()} className="btn-primary inline-flex items-center gap-2"><Send className="w-4 h-4" /> Submit for final</button>}<button type="button" onClick={() => setSelected(null)} className="btn-ghost" aria-label="Close active encounter"><X className="w-5 h-5" /></button></div>
          </div>
          <div className="flex-1 overflow-auto p-3 sm:p-5"><div className="grid gap-5 lg:grid-cols-[minmax(280px,340px)_minmax(0,1fr)]"><ClinicalSafetyContext patientId={activePatientId} encounterId={selected.id} /><div className="space-y-5">
            <section className="rounded-2xl border border-border bg-card p-5"><div className="flex flex-wrap items-center justify-between gap-3"><div><h3 className="font-semibold flex items-center gap-2"><FileText className="w-4 h-4 text-primary" /> Encounter details</h3><p className="text-xs text-muted-foreground mt-1">Auditable clinical entry surface</p></div><span className="text-xs text-muted-foreground inline-flex items-center gap-1"><UserRound className="w-3.5 h-3.5" /> {selected.practitioner_id === user?.id ? 'Created by you' : 'Attending clinician'}</span></div><div className="mt-4 grid gap-4 md:grid-cols-2"><div><h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Symptoms / presentation</h4><p className="mt-2 text-sm whitespace-pre-wrap">{selected.symptoms || '—'}</p></div><div><h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Clerking / history</h4><p className="mt-2 text-sm whitespace-pre-wrap">{selected.clerking_notes || '—'}</p></div></div></section>
            <section className="rounded-2xl border border-border bg-card p-5"><div className="flex items-center justify-between gap-3 mb-3"><div><h3 className="font-semibold">Diagnoses</h3><p className="text-xs text-muted-foreground">New diagnoses are provisional by default. Mark the diagnosis driving treatment as principal.</p></div><span className="rounded-full bg-muted px-2.5 py-1 text-[10px] font-medium">{diagnoses.length} documented</span></div>{selected.status !== 'completed' && <div className="flex gap-2 mb-3"><input value={newDx} onChange={(e) => setNewDx(e.target.value)} placeholder="Add coded diagnosis" className="input-medical flex-1" /><button type="button" onClick={addDiagnosis} className="btn-primary">Add provisional</button></div>}<div className="space-y-2">{diagnoses.map((dx) => <div key={dx.id} className="rounded-xl border border-border p-3 flex items-center justify-between gap-3"><div><span className="font-medium text-sm">{dx.diagnosis}</span>{dx.is_principal ? <span className="ml-2 text-xs rounded-full bg-primary/10 text-primary px-2 py-1">Principal</span> : <span className="ml-2 text-xs rounded-full bg-muted px-2 py-1">Provisional</span>}</div>{selected.status !== 'completed' && <div className="flex gap-2">{!dx.is_principal && <button type="button" onClick={() => void setPrincipal(dx)} className="btn-ghost text-xs">Set principal</button>}<button type="button" onClick={() => void removeDiagnosis(dx.id)} className="text-destructive p-2" aria-label="Remove diagnosis"><Trash2 className="w-4 h-4" /></button></div>}</div>)}</div></section>
            <section className="rounded-2xl border border-border bg-card p-5"><div className="flex items-center justify-between gap-3 mb-3"><div><h3 className="font-semibold flex items-center gap-2"><Pill className="w-4 h-4" /> Prescribing</h3><p className="text-xs text-muted-foreground">Treatment can be initiated when clinically indicated; diagnosis remains explicitly documented.</p></div><span className="text-xs text-muted-foreground">{prescriptions.length} prescription(s)</span></div>{selected.status !== 'completed' && <form onSubmit={addPrescription} className="grid gap-2 md:grid-cols-2"><input value={med} onChange={(e) => setMed(e.target.value)} placeholder="Medication" className="input-medical" required /><input value={dose} onChange={(e) => setDose(e.target.value)} placeholder="Dose" className="input-medical" /><input value={freq} onChange={(e) => setFreq(e.target.value)} placeholder="Frequency" className="input-medical" /><input value={duration} onChange={(e) => setDuration(e.target.value)} placeholder="Duration" className="input-medical" /><button type="submit" className="btn-primary md:col-span-2">Add prescription</button></form>}<div className="space-y-2 mt-3">{prescriptions.map((rx) => <div key={rx.id} className="rounded-xl border border-border p-3 text-sm flex justify-between gap-3"><span><b>{rx.medication}</b> · {rx.dosage || 'Dose not recorded'} · {rx.frequency || 'Frequency not recorded'} · {rx.duration || 'Duration not recorded'}</span><span className="text-xs text-muted-foreground">{rx.status}</span></div>)}</div></section>
          </div></div></div>
        </div>
      </div>}
    </div>
  );
}
