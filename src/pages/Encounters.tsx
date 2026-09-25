import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  AlertTriangle,
  BedDouble,
  CheckCircle2,
  Clock3,
  Pencil,
  Save,
  Send,
  FileText,
  HeartPulse,
  History,
  Pill,
  Plus,
  ShieldAlert,
  Stethoscope,
  Trash2,
  UserRound,
  X,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { toast } from "@/hooks/use-toast";

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
  practitioner_id?: string | null;
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
  diagnosis_id?: string | null;
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
      const { data, error } = await db.rpc("get_patient_bmi_context", { _patient_id: patientId });
      if (!active) return;
      if (error) {
        toast({ title: "BMI context unavailable", description: error.message, variant: "destructive" });
        return;
      }
      setBmi((data?.[0] ?? null) as BMIContext | null);
    };
    void load();
    return () => {
      active = false;
    };
  }, [patientId]);
  return (
    <section className="rounded-xl border border-primary/30 bg-primary/5 p-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h4 className="text-sm font-semibold flex items-center gap-2"><HeartPulse className="w-4 h-4 text-primary" /> BMI clinical context</h4>
          <p className="text-[11px] text-muted-foreground mt-1">Latest server-calculated measurement</p>
        </div>
        <span className="text-2xl font-bold">{bmi?.bmi ?? "—"}</span>
      </div>
      {bmi && (
        <div className="grid grid-cols-2 gap-2 mt-3 text-xs">
          <span>Category: <b>{bmi.category}</b></span>
          <span>Weight: <b>{bmi.weight_kg ?? "—"} kg</b></span>
          <span>Height: <b>{bmi.height_m ?? "—"} m</b></span>
          <span>Recorded: <b>{bmi.recorded_at ? new Date(bmi.recorded_at).toLocaleDateString() : "—"}</b></span>
        </div>
      )}
      <p className="text-[11px] text-muted-foreground mt-3">BMI is one clinical input alongside age, pregnancy status, diagnoses, examination findings, renal/hepatic function, allergies and medication-specific guidance. It does not automatically determine a prescription or dose.</p>
    </section>
  );
}

function ClinicalSafetyContext({ patientId, encounterId }: { patientId: string; encounterId?: string }) {
  const [context, setContext] = useState<ClinicalContext | null>(null);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    let active = true;
    const load = async () => {
      setLoading(true);
      const { data, error } = await db.rpc("get_encounter_clinical_context", { _patient_id: patientId, _encounter_id: encounterId ?? null });
      if (!active) return;
      if (error) toast({ title: "Clinical history unavailable", description: error.message, variant: "destructive" });
      setContext((data ?? null) as ClinicalContext | null);
      setLoading(false);
    };
    void load();
    return () => {
      active = false;
    };
  }, [patientId, encounterId]);
  const patient = context?.patient;
  const conditions = useMemo(() => {
    const historical = (context?.previous_encounters ?? []).flatMap((e) => [e.principal_diagnosis, ...e.diagnoses]).filter((v): v is string => Boolean(v));
    const chronic = patient?.chronic_conditions?.split(/[,;\n]+/) ?? [];
    return Array.from(new Set([...chronic, ...historical].map((v) => v.trim()).filter(Boolean))).slice(0, 12);
  }, [context, patient]);
  return (
    <aside className="card-medical p-5 space-y-4 border-l-4 border-l-critical/70 lg:sticky lg:top-4 lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto">
      <div className="flex items-start justify-between gap-3">
        <div><h3 className="font-semibold flex items-center gap-2"><ShieldAlert className="w-4 h-4 text-critical" /> Patient safety context</h3><p className="text-xs text-muted-foreground mt-1">High-value history stays beside the active encounter.</p></div>
        {loading && <span className="text-xs text-muted-foreground">Loading…</span>}
      </div>
      {patient && (
        <section className="rounded-xl border border-border p-3">
          <p className="font-medium text-sm">{patient.name}</p>
          <p className="text-xs text-muted-foreground">{patient.patient_code}</p>
          <div className="grid grid-cols-2 gap-2 mt-3 text-xs">
            <div>Blood group<p className="font-medium">{patient.blood_group || "Not recorded"}</p></div>
            <div>Genotype<p className="font-medium">{patient.genotype || "Not recorded"}</p></div>
          </div>
        </section>
      )}
      <BMIContextCard patientId={patientId} />
      {patient?.allergies && <section className="rounded-xl border border-critical/40 bg-critical/5 p-4"><div className="flex items-center gap-2 font-semibold text-sm text-critical"><AlertTriangle className="w-4 h-4" /> Allergies / alerts</div><p className="text-sm mt-2 whitespace-pre-wrap">{patient.allergies}</p></section>}
      {conditions.length > 0 && <section className="rounded-xl border border-warning/40 bg-warning/5 p-4"><div className="flex items-center gap-2 font-semibold text-sm mb-2"><AlertTriangle className="w-4 h-4" /> Conditions to notice</div><div className="flex flex-wrap gap-2">{conditions.map((condition) => <span key={condition} className="rounded-full bg-background border border-warning/40 px-2.5 py-1 text-xs font-medium">{condition}</span>)}</div></section>}
      {context?.recent_vitals?.[0] && (
        <section className="rounded-xl border border-border p-4">
          <h4 className="text-sm font-semibold flex items-center gap-2"><HeartPulse className="w-4 h-4" /> Latest recorded vitals</h4>
          <p className="text-[11px] text-muted-foreground mt-1">{new Date(context.recent_vitals[0].recorded_at).toLocaleString()}</p>
          <div className="grid grid-cols-2 gap-2 mt-3 text-xs">
            <span>BP: <b>{context.recent_vitals[0].systolic ?? "—"}/{context.recent_vitals[0].diastolic ?? "—"}</b></span>
            <span>Pulse: <b>{context.recent_vitals[0].pulse_rate ?? "—"}</b></span>
            <span>Temp: <b>{context.recent_vitals[0].temperature ?? "—"}</b></span>
            <span>SpO₂: <b>{context.recent_vitals[0].oxygen_saturation ?? "—"}%</b></span>
          </div>
        </section>
      )}
      <section>
        <h4 className="text-sm font-semibold mb-2 flex items-center gap-2"><History className="w-4 h-4 text-primary" /> Previous encounters</h4>
        {!context?.previous_encounters?.length ? <p className="text-sm text-muted-foreground">No previous encounters recorded.</p> : <div className="space-y-3">{context.previous_encounters.map((item) => <article key={item.id} className="rounded-xl border border-border p-3 bg-background/70"><div className="flex justify-between gap-2"><span className="text-xs text-muted-foreground">{new Date(item.created_at).toLocaleString()}</span><span className="text-xs rounded-full bg-muted px-2 py-0.5">{item.status}</span></div><p className="text-sm font-semibold mt-2">{item.principal_diagnosis || item.diagnoses[0] || "Clinical encounter"}</p>{item.symptoms && <p className="text-xs mt-2"><b>Presentation:</b> {item.symptoms}</p>}{item.treatment_plan && <p className="text-xs text-muted-foreground mt-1"><b className="text-foreground">Previous plan:</b> {item.treatment_plan}</p>}</article>)}</div>}
      </section>
    </aside>
  );
}

function encounterAge(createdAt: string) {
  const ageMs = Math.max(0, Date.now() - new Date(createdAt).getTime());
  const minutes = Math.floor(ageMs / 60000);
  if (minutes < 60) return `${minutes}m old`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h old`;
  return `${Math.floor(hours / 24)}d old`;
}

export default function Encounters() {
  const [searchParams] = useSearchParams();
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [encounters, setEncounters] = useState<Encounter[]>([]);
  const [selected, setSelected] = useState<Encounter | null>(null);
  const [isHistoryOpen, setIsHistoryOpen] = useState(true);
  const [admitting, setAdmitting] = useState(false);
  const [diagnoses, setDiagnoses] = useState<Diagnosis[]>([]);
  const [prescriptions, setPrescriptions] = useState<Prescription[]>([]);
  const [patientId, setPatientId] = useState(searchParams.get("patient") || "");
  const [symptoms, setSymptoms] = useState("");
  const [clerking, setClerking] = useState("");
  const [newDx, setNewDx] = useState("");
  const [med, setMed] = useState("");
  const [dose, setDose] = useState("");
  const [freq, setFreq] = useState("");
  const [duration, setDuration] = useState("");
  const [selectedDiagnosisId, setSelectedDiagnosisId] = useState("");
  const [amending, setAmending] = useState(false);
  const [amendmentReason, setAmendmentReason] = useState("");
  const [amendmentBusy, setAmendmentBusy] = useState(false);
  const [amendmentSymptoms, setAmendmentSymptoms] = useState("");
  const [amendmentClerking, setAmendmentClerking] = useState("");
  const [amendmentPrincipal, setAmendmentPrincipal] = useState("");
  const [amendmentPlan, setAmendmentPlan] = useState("");
  const [versionHistory, setVersionHistory] = useState<any[]>([]);
  const [auditHistory, setAuditHistory] = useState<any[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [showVersionHistory, setShowVersionHistory] = useState(false);
  const activePatientId = selected?.patient_id || patientId;

  const loadAll = async () => {
    const [{ data: pts }, { data: encs }] = await Promise.all([
      supabase.from("patients").select("id, first_name, last_name, patient_code").order("created_at", { ascending: false }).limit(200),
      supabase.from("encounters").select("id, patient_id, symptoms, clerking_notes, principal_diagnosis, treatment_plan, status, admission_id, created_at, practitioner_id, submitted_at, version_no").order("created_at", { ascending: false }).limit(50),
    ]);
    setPatients((pts ?? []) as Patient[]);
    setEncounters((encs ?? []) as Encounter[]);
  };

  const loadDetails = async (id: string) => {
    const [{ data: dx }, { data: rx }] = await Promise.all([
      supabase.from("diagnoses").select("id, encounter_id, diagnosis, is_principal").eq("encounter_id", id),
      supabase.from("prescriptions").select("id, encounter_id, medication, dosage, frequency, duration, status, diagnosis_id").eq("encounter_id", id).order("created_at", { ascending: false }),
    ]);
    setDiagnoses((dx ?? []) as Diagnosis[]);
    setPrescriptions((rx ?? []) as Prescription[]);
  };

  useEffect(() => { void loadAll(); }, []);
  useEffect(() => {
    const id = searchParams.get("encounter");
    const p = searchParams.get("patient");
    if (p) setPatientId(p);
    if (id) {
      const found = encounters.find((e) => e.id === id);
      if (found) {
        setSelected(found);
        setIsHistoryOpen(false);
      }
    }
  }, [searchParams, encounters]);
  useEffect(() => {
    if (selected) void loadDetails(selected.id);
  }, [selected]);

  const loadHistory = async (encounterId: string) => {
    setHistoryLoading(true);
    const [{ data: versions, error: versionError }, { data: audits, error: auditError }] = await Promise.all([
      supabase.from("document_versions").select("id,entity_type,entity_id,version_no,action,snapshot,changed_by,changed_at").eq("entity_type", "encounter").eq("entity_id", encounterId).order("version_no", { ascending: false }),
      supabase.from("system_audit_log").select("id,actor_id,action,module,entity_type,entity_id,severity,metadata,created_at").eq("entity_type", "encounter").eq("entity_id", encounterId).order("created_at", { ascending: false }).limit(50),
    ]);
    setHistoryLoading(false);
    if (versionError || auditError) {
      toast({ title: "History unavailable", description: versionError?.message ?? auditError?.message, variant: "destructive" });
      return;
    }
    setVersionHistory(versions ?? []);
    setAuditHistory(audits ?? []);
    setShowVersionHistory(true);
  };

  const createEncounter = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!patientId) return toast({ title: "Select a patient", variant: "destructive" });
    const { data, error } = await db.rpc("create_encounter_workflow", { _patient_id: patientId, _symptoms: symptoms || null, _clerking_notes: clerking || null });
    if (error) return toast({ title: "Encounter creation failed", description: error.message, variant: "destructive" });
    setSymptoms("");
    setClerking("");
    setSelected(data as Encounter);
    setIsHistoryOpen(false);
    void loadAll();
  };

  const addDiagnosis = async () => {
    if (!selected || !newDx.trim()) return toast({ title: "Enter a diagnosis", description: "Document a provisional diagnosis before adding it.", variant: "destructive" });
    const { error } = await db.rpc("add_encounter_diagnosis", { _encounter_id: selected.id, _diagnosis: newDx.trim() });
    if (error) return toast({ title: "Diagnosis failed", description: error.message, variant: "destructive" });
    setNewDx("");
    void loadDetails(selected.id);
  };

  const setPrincipal = async (dx: Diagnosis) => {
    if (!selected) return;
    const { data, error } = await db.rpc("set_principal_diagnosis", { _encounter_id: selected.id, _diagnosis_id: dx.id });
    if (error) return toast({ title: "Principal diagnosis failed", description: error.message, variant: "destructive" });
    setSelected({ ...selected, principal_diagnosis: data?.diagnosis ?? dx.diagnosis });
    void loadDetails(selected.id);
  };

  const removeDiagnosis = async (id: string) => {
    if (!selected) return;
    const { error } = await db.rpc("remove_encounter_diagnosis", { _diagnosis_id: id });
    if (error) return toast({ title: "Diagnosis removal failed", description: error.message, variant: "destructive" });
    void loadDetails(selected.id);
  };

  const addPrescription = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!selected || !med.trim()) return;
    const { error } = await db.rpc("create_encounter_prescription", { _encounter_id: selected.id, _medication: med.trim(), _dosage: dose || null, _frequency: freq || null, _duration: duration || null, _diagnosis_id: selectedDiagnosisId || null });
    if (error) return toast({ title: "Prescription failed", description: error.message, variant: "destructive" });
    setMed("");
    setDose("");
    setFreq("");
    setDuration("");
    setSelectedDiagnosisId("");
    void loadDetails(selected.id);
  };

  const admitEncounter = async () => {
    if (!selected || admitting) return;
    const reason = window.prompt("Admission reason", selected.principal_diagnosis || "Clinical admission");
    if (reason === null) return;
    const ward = window.prompt("Ward (optional)", "") ?? "";
    setAdmitting(true);
    const { data, error } = await db.rpc("admit_encounter_workflow", { _encounter_id: selected.id, _reason: reason.trim() || "Clinical admission", _ward: ward.trim() || null, _emergency_override: true });
    setAdmitting(false);
    if (error) return toast({ title: "Admission failed", description: error.message, variant: "destructive" });
    toast({ title: data?.override ? "Emergency admission activated" : "Patient admitted", description: data?.override ? "Eligible pending services were released for emergency treatment before deposit." : "The admission has been recorded." });
    setSelected({ ...selected, admission_id: data?.admission_id ?? selected.admission_id });
    void loadAll();
  };

  const submitEncounter = async () => {
    if (!selected) return;
    const { data, error } = await db.rpc("submit_encounter_workflow", { _encounter_id: selected.id, _specialty: null, _appointment_date: null, _referral_reason: null });
    if (error) return toast({ title: "Encounter submission failed", description: error.message, variant: "destructive" });
    setSelected({ ...selected, status: "completed", submitted_at: new Date().toISOString(), version_no: data?.version_no ?? selected.version_no ?? 1 });
    toast({ title: "Encounter submitted", description: "The final clinical document has been locked and versioned." });
    void loadAll();
  };

  const beginAmendment = () => {
    if (!selected || selected.status !== "completed") return;
    setAmendmentSymptoms(selected.symptoms ?? "");
    setAmendmentClerking(selected.clerking_notes ?? "");
    setAmendmentPrincipal(selected.principal_diagnosis ?? "");
    setAmendmentPlan(selected.treatment_plan ?? "");
    setAmendmentReason("");
    setAmending(true);
  };

  const saveAmendment = async () => {
    if (!selected || !amendmentReason.trim() || amendmentBusy) return;
    setAmendmentBusy(true);
    const { data, error } = await db.rpc("amend_encounter_workflow", {
      _encounter_id: selected.id,
      _symptoms: amendmentSymptoms || null,
      _clerking_notes: amendmentClerking || null,
      _principal_diagnosis: amendmentPrincipal || null,
      _treatment_plan: amendmentPlan || null,
      _reason: amendmentReason.trim(),
    });
    setAmendmentBusy(false);
    if (error) return toast({ title: "Amendment failed", description: error.message, variant: "destructive" });
    setSelected({ ...selected, symptoms: amendmentSymptoms || null, clerking_notes: amendmentClerking || null, principal_diagnosis: amendmentPrincipal || null, treatment_plan: amendmentPlan || null, version_no: data?.version_no ?? (selected.version_no ?? 1) + 1 });
    setAmending(false);
    toast({ title: "Encounter amended", description: "The previous finalized version remains preserved in the audit history." });
    void loadAll();
  };

  const selectEncounter = (item: Encounter) => {
    setSelected(item);
    setIsHistoryOpen(false);
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <header className="rounded-3xl border border-border bg-card p-5 shadow-sm sm:p-7">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="mb-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">Patient Care · Longitudinal encounter record</p>
            <h1 className="text-2xl font-heading font-bold tracking-tight flex items-center gap-2"><Stethoscope className="w-6 h-6 text-primary" /> Encounter Workspace</h1>
            <p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">Historical encounters are the primary selection surface. Open a complete clinical document in one focused workspace without leaving the encounter page.</p>
          </div>
          <button type="button" onClick={() => setIsHistoryOpen(true)} className="btn-secondary inline-flex items-center gap-2"><History className="w-4 h-4" /> Encounter history</button>
        </div>
      </header>

      <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(300px,360px)]">
        <form onSubmit={createEncounter} className="card-medical p-5 space-y-4">
          <div className="flex items-start justify-between gap-3">
            <div><h2 className="font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> New encounter</h2><p className="mt-1 text-xs text-muted-foreground">Save creates a draft. Final submission happens only after the clinical document is complete.</p></div>
            <span className="rounded-full border border-warning/40 bg-warning/5 px-2.5 py-1 text-[10px] font-semibold text-warning">Draft-first</span>
          </div>
          <select value={patientId} onChange={(e) => setPatientId(e.target.value)} className="input-medical w-full" required><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name} ({p.patient_code})</option>)}</select>
          <div className="grid gap-3 md:grid-cols-2"><textarea value={symptoms} onChange={(e) => setSymptoms(e.target.value)} placeholder="Presenting symptoms / complaints" className="input-medical w-full" rows={4} /><textarea value={clerking} onChange={(e) => setClerking(e.target.value)} placeholder="Clerking / history notes" className="input-medical w-full" rows={4} /></div>
          <button type="submit" className="btn-primary inline-flex items-center gap-2"><FileText className="w-4 h-4" /> Save draft</button>
        </form>
        <section className="card-medical p-5">
          <div className="flex items-center justify-between gap-3 mb-3"><div><h2 className="font-semibold flex items-center gap-2"><History className="w-4 h-4 text-primary" /> Recent encounters</h2><p className="text-xs text-muted-foreground mt-1">{encounters.length} recent records</p></div><button type="button" onClick={() => setIsHistoryOpen(true)} className="text-xs text-primary">View all</button></div>
          <div className="space-y-2 max-h-[320px] overflow-auto">{encounters.slice(0, 8).map((item) => { const p = patients.find((x) => x.id === item.patient_id); const active = selected?.id === item.id; return <button type="button" key={item.id} onClick={() => selectEncounter(item)} className={`w-full rounded-xl border p-3 text-left transition-colors ${active ? "border-primary bg-primary/5" : "border-border hover:bg-accent/40"}`}><div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="font-medium text-sm truncate">{p ? `${p.first_name} ${p.last_name}` : "Patient record"}</p><p className="text-xs text-muted-foreground">{p?.patient_code ?? item.patient_id} · {new Date(item.created_at).toLocaleDateString()}</p></div><span className="shrink-0 rounded-full bg-muted px-2 py-1 text-[10px] capitalize">{item.status}</span></div><p className="mt-2 text-xs text-muted-foreground truncate">{item.principal_diagnosis || item.symptoms || "Clinical encounter"}</p></button>; })}</div>
        </section>
      </section>

      {isHistoryOpen && (
        <div className="fixed inset-0 z-[70] bg-background/80 backdrop-blur-sm p-4 sm:p-8" role="dialog" aria-modal="true" aria-labelledby="encounter-history-title">
          <div className="mx-auto flex h-full max-w-5xl flex-col overflow-hidden rounded-3xl border border-border bg-card shadow-2xl">
            <div className="flex items-center justify-between gap-3 border-b border-border p-5">
              <div><h2 id="encounter-history-title" className="text-lg font-semibold">Patient encounter history</h2><p className="text-xs text-muted-foreground">Select an entire row to open the clinical document.</p></div>
              <button type="button" onClick={() => setIsHistoryOpen(false)} className="btn-ghost" aria-label="Close encounter history"><X className="w-5 h-5" /></button>
            </div>
            <div className="flex-1 overflow-auto p-4">
              <div className="overflow-hidden rounded-2xl border border-border">
                {encounters.map((item) => {
                  const p = patients.find((x) => x.id === item.patient_id);
                  const creator = item.practitioner_id === user?.id ? "You" : "Clinical staff";
                  return <button type="button" key={item.id} onClick={() => selectEncounter(item)} className="grid w-full grid-cols-1 gap-3 border-b border-border p-4 text-left last:border-b-0 hover:bg-muted/40 focus-visible:bg-muted/40 md:grid-cols-[minmax(0,1.6fr)_minmax(110px,0.8fr)_minmax(120px,0.9fr)_90px]">
                    <div className="min-w-0"><p className="font-medium truncate">{p ? `${p.first_name} ${p.last_name}` : "Patient record"}</p><p className="text-xs text-muted-foreground truncate">{p?.patient_code ?? item.patient_id}</p></div>
                    <div><p className="text-xs text-muted-foreground">Date</p><p className="text-sm">{new Date(item.created_at).toLocaleDateString()}</p><p className="text-[10px] text-muted-foreground">{encounterAge(item.created_at)}</p></div>
                    <div><p className="text-xs text-muted-foreground">Created by</p><p className="text-sm">{creator}</p><p className="text-[10px] text-muted-foreground">Version {item.version_no ?? 1}</p></div>
                    <div className="flex items-start justify-start md:justify-end"><span className="rounded-full bg-muted px-2 py-1 text-[10px] capitalize">{item.status}</span></div>
                  </button>;
                })}
                {!encounters.length && <div className="p-10 text-center text-sm text-muted-foreground">No historical encounters are available.</div>}
              </div>
            </div>
          </div>
        </div>
      )}

      {selected && (
        <div className="fixed inset-0 z-[65] bg-slate-950/55 backdrop-blur-sm p-2 sm:p-4" role="dialog" aria-modal="true" aria-labelledby="active-encounter-title">
          <div className="mx-auto flex h-full max-w-7xl flex-col overflow-hidden rounded-3xl border border-border bg-background shadow-2xl">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border bg-card p-4 sm:p-5">
              <div className="min-w-0">
                <p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-primary">Active clinical document</p>
                <h2 id="active-encounter-title" className="mt-1 text-lg font-semibold truncate">Encounter · {patients.find((p) => p.id === selected.patient_id)?.first_name ?? "Patient"} {patients.find((p) => p.id === selected.patient_id)?.last_name ?? ""}</h2>
                <p className="text-xs text-muted-foreground">{patients.find((p) => p.id === selected.patient_id)?.patient_code ?? selected.patient_id} · {new Date(selected.created_at).toLocaleString()} · {encounterAge(selected.created_at)}</p>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <span className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold ${selected.status === "completed" ? "bg-success/10 text-success" : "bg-warning/10 text-warning"}`}><Clock3 className="w-3.5 h-3.5" />{selected.status === "completed" ? `Submitted · v${selected.version_no ?? 1}` : "Draft"}</span>
                {selected.status === "completed" && <button type="button" onClick={beginAmendment} className="btn-secondary inline-flex items-center gap-2"><Pencil className="w-4 h-4" /> Amend</button>}
                <button type="button" onClick={() => void loadHistory(selected.id)} className="btn-secondary inline-flex items-center gap-2"><History className="w-4 h-4" /> Version history</button>
                {selected.status === "completed" && !selected.admission_id && <button type="button" onClick={() => void admitEncounter()} disabled={admitting} className="btn-primary inline-flex items-center gap-2"><BedDouble className="w-4 h-4" />{admitting ? "Admitting…" : "Initiate admission"}</button>}
                {selected.admission_id && <span className="inline-flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/5 px-3 py-2 text-sm font-medium text-primary"><BedDouble className="w-4 h-4" /> Admission active</span>}
                {selected.status !== "completed" && <button type="button" onClick={() => void submitEncounter()} className="btn-primary inline-flex items-center gap-2"><Send className="w-4 h-4" /> Submit for final</button>}
                <button type="button" onClick={() => setSelected(null)} className="btn-ghost" aria-label="Close active encounter"><X className="w-5 h-5" /></button>
              </div>
            </div>
            {amending && selected.status === "completed" && <section className="mb-5 rounded-2xl border border-warning/40 bg-warning/5 p-5">
              <div className="flex items-start justify-between gap-3"><div><h3 className="font-semibold flex items-center gap-2"><Pencil className="w-4 h-4" /> Amend finalized encounter</h3><p className="mt-1 text-xs text-muted-foreground">Amendments create a new document version. The previous finalized snapshot remains preserved.</p></div><span className="rounded-full border border-warning/40 px-2 py-1 text-[10px] font-semibold">Version {selected.version_no ?? 1} → {(selected.version_no ?? 1) + 1}</span></div>
              <div className="mt-4 grid gap-3 md:grid-cols-2"><textarea value={amendmentSymptoms} onChange={(e) => setAmendmentSymptoms(e.target.value)} className="input-medical" rows={4} placeholder="Symptoms / presentation" /><textarea value={amendmentClerking} onChange={(e) => setAmendmentClerking(e.target.value)} className="input-medical" rows={4} placeholder="Clerking / history" /><input value={amendmentPrincipal} onChange={(e) => setAmendmentPrincipal(e.target.value)} className="input-medical" placeholder="Principal diagnosis" /><textarea value={amendmentPlan} onChange={(e) => setAmendmentPlan(e.target.value)} className="input-medical" rows={3} placeholder="Treatment plan" /></div>
              <div className="mt-3"><label className="text-xs font-semibold">Amendment reason</label><textarea value={amendmentReason} onChange={(e) => setAmendmentReason(e.target.value)} className="input-medical mt-1 w-full" rows={2} placeholder="Why is this finalized clinical document being amended?" required /></div>
              <div className="mt-4 flex flex-wrap justify-end gap-2"><button type="button" onClick={() => setAmending(false)} className="btn-ghost">Cancel</button><button type="button" onClick={() => void saveAmendment()} disabled={amendmentBusy || !amendmentReason.trim()} className="btn-primary inline-flex items-center gap-2"><Save className="w-4 h-4" />{amendmentBusy ? "Saving…" : "Save amendment"}</button></div>
            </section>}
            <div className="flex-1 overflow-auto p-3 sm:p-5">
              <div className="grid gap-5 lg:grid-cols-[minmax(280px,340px)_minmax(0,1fr)]">
                <ClinicalSafetyContext patientId={activePatientId} encounterId={selected.id} />
                <div className="space-y-5">
                  <section className="rounded-2xl border border-border bg-card p-5">
                    <div className="flex flex-wrap items-center justify-between gap-3"><div><h3 className="font-semibold flex items-center gap-2"><FileText className="w-4 h-4 text-primary" /> Encounter details</h3><p className="text-xs text-muted-foreground mt-1">Auditable clinical entry surface</p></div><span className="text-xs text-muted-foreground inline-flex items-center gap-1"><UserRound className="w-3.5 h-3.5" /> {selected.practitioner_id === user?.id ? "Created by you" : "Attending clinician"}</span></div>
                    <div className="mt-4 grid gap-4 md:grid-cols-2"><div><h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Symptoms / presentation</h4><p className="mt-2 text-sm whitespace-pre-wrap">{selected.symptoms || "—"}</p></div><div><h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Clerking / history</h4><p className="mt-2 text-sm whitespace-pre-wrap">{selected.clerking_notes || "—"}</p></div></div>
                  </section>
                  <section className="rounded-2xl border border-border bg-card p-5">
                    <div className="flex items-center justify-between gap-3 mb-3"><div><h3 className="font-semibold">Diagnoses</h3><p className="text-xs text-muted-foreground">New diagnoses are provisional by default. Mark the diagnosis driving treatment as principal.</p></div><span className="rounded-full bg-muted px-2.5 py-1 text-[10px] font-medium">{diagnoses.length} documented</span></div>
                    {selected.status !== "completed" && <div className="flex gap-2 mb-3"><input value={newDx} onChange={(e) => setNewDx(e.target.value)} placeholder="Add provisional diagnosis" className="input-medical flex-1" /><button type="button" onClick={() => void addDiagnosis()} className="btn-primary">Add</button></div>}
                    <div className="space-y-2">{diagnoses.map((dx) => <div key={dx.id} className="rounded-xl border border-border p-3 flex items-center justify-between gap-3"><div><span className="font-medium text-sm">{dx.diagnosis}</span>{dx.is_principal ? <span className="ml-2 text-xs rounded-full bg-primary/10 text-primary px-2 py-1">Principal</span> : <span className="ml-2 text-xs rounded-full bg-muted px-2 py-1">Provisional</span>}</div>{selected.status !== "completed" && <div className="flex gap-2">{!dx.is_principal && <button type="button" onClick={() => void setPrincipal(dx)} className="btn-ghost text-xs">Set principal</button>}<button type="button" onClick={() => void removeDiagnosis(dx.id)} className="text-destructive p-2" aria-label="Remove diagnosis"><Trash2 className="w-4 h-4" /></button></div>}</div>)}</div>
                  </section>
                  <section className="rounded-2xl border border-border bg-card p-5">
                    <div className="flex items-center justify-between gap-3 mb-3"><div><h3 className="font-semibold flex items-center gap-2"><Pill className="w-4 h-4" /> Prescribing</h3><p className="text-xs text-muted-foreground">Treatment remains explicitly linked to the documented clinical assessment.</p></div><span className="text-xs text-muted-foreground">{prescriptions.length} prescription(s)</span></div>
                    {selected.status !== "completed" && <form onSubmit={addPrescription} className="grid gap-2 md:grid-cols-2"><select value={selectedDiagnosisId} onChange={(e) => setSelectedDiagnosisId(e.target.value)} className="input-medical md:col-span-2" required><option value="">Select diagnosis being treated…</option>{diagnoses.map((dx) => <option key={dx.id} value={dx.id}>{dx.diagnosis}{dx.is_principal ? " · Principal" : ""}</option>)}</select><input value={med} onChange={(e) => setMed(e.target.value)} placeholder="Medication" className="input-medical" required /><input value={dose} onChange={(e) => setDose(e.target.value)} placeholder="Dose" className="input-medical" /><input value={freq} onChange={(e) => setFreq(e.target.value)} placeholder="Frequency" className="input-medical" /><input value={duration} onChange={(e) => setDuration(e.target.value)} placeholder="Duration" className="input-medical" /><button type="submit" disabled={!diagnoses.length} className="btn-primary md:col-span-2">Add prescription</button></form>}
                    <div className="space-y-2 mt-3">{prescriptions.map((rx) => <div key={rx.id} className="rounded-xl border border-border p-3 text-sm flex justify-between gap-3"><span><b>{rx.medication}</b> · {rx.dosage || "Dose not recorded"} · {rx.frequency || "Frequency not recorded"} · {rx.duration || "Duration not recorded"}</span><span className="text-xs text-muted-foreground">{rx.status}</span></div>)}</div>
                  </section>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
      {showVersionHistory && selected && (
        <div className="fixed inset-0 z-[80] bg-slate-950/60 backdrop-blur-sm p-3 sm:p-6" role="dialog" aria-modal="true" aria-labelledby="encounter-version-history-title">
          <div className="mx-auto flex h-full max-w-6xl flex-col overflow-hidden rounded-3xl border border-border bg-background shadow-2xl">
            <div className="flex items-center justify-between gap-3 border-b border-border bg-card p-5">
              <div><p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-primary">Audit & document history</p><h2 id="encounter-version-history-title" className="text-lg font-semibold">Encounter version history</h2><p className="text-xs text-muted-foreground">Finalized versions remain immutable snapshots; amendments create a new version.</p></div>
              <button type="button" onClick={() => setShowVersionHistory(false)} className="btn-ghost" aria-label="Close version history"><X className="w-5 h-5" /></button>
            </div>
            <div className="flex-1 overflow-auto p-5 space-y-6">
              {historyLoading ? <div className="p-8 text-center text-sm text-muted-foreground">Loading audit history…</div> : <>
                <section><h3 className="mb-3 flex items-center gap-2 font-semibold"><History className="h-4 w-4 text-primary" /> Document versions</h3><div className="space-y-3">{versionHistory.map((v) => <article key={v.id} className="rounded-2xl border border-border bg-card p-4"><div className="flex flex-wrap items-center justify-between gap-2"><div><span className="font-semibold">Version {v.version_no}</span><span className="ml-2 rounded-full bg-muted px-2 py-1 text-[10px] uppercase">{v.action}</span></div><span className="text-xs text-muted-foreground">{new Date(v.changed_at).toLocaleString()}</span></div><p className="mt-2 text-xs text-muted-foreground">Changed by: {v.changed_by === user?.id ? "You" : v.changed_by || "Recorded clinical actor"}</p></article>)}{!versionHistory.length && <p className="text-sm text-muted-foreground">No version snapshots are available yet.</p>}</div></section>
                <section><h3 className="mb-3 flex items-center gap-2 font-semibold"><ShieldAlert className="h-4 w-4 text-critical" /> Audit events</h3><div className="space-y-2">{auditHistory.map((a) => <article key={a.id} className="rounded-xl border border-border p-3"><div className="flex flex-wrap justify-between gap-2"><div><span className="font-medium text-sm">{a.action}</span><span className="ml-2 text-[10px] uppercase text-muted-foreground">{a.severity || "info"}</span></div><span className="text-xs text-muted-foreground">{new Date(a.created_at).toLocaleString()}</span></div><p className="mt-1 text-xs text-muted-foreground">Actor: {a.actor_id === user?.id ? "You" : a.actor_id || "System"}</p></article>)}{!auditHistory.length && <p className="text-sm text-muted-foreground">No audit events are available for this encounter.</p>}</div></section>
              </>}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
