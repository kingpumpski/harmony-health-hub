import RefreshButton from '@/components/ui/RefreshButton';
// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { toast } from 'sonner';
import { ArrowLeft, CalendarDays, RefreshCw, Activity, Stethoscope, FlaskConical, Pill, CreditCard, FileText, BedDouble, Save, UserRound } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { getPatientById, updatePatient } from '@/lib/healthApi';
import { useAuth } from '@/contexts/AuthContext';
import TriageHistoryChart from '@/components/triage/TriageHistoryChart';
import TriageRecordForm from '@/components/triage/TriageRecordForm';
import { normalizePatientId, selectTriageParameter, type TriageHistoryRecord, type TriageParameter } from '@/lib/triagePresentation';
import PatientAvatar from '@/components/patients/PatientAvatar';

type TabKey = 'profile' | 'appointments' | 'vitals' | 'encounters' | 'labs' | 'prescriptions' | 'billing' | 'documents' | 'admission';
const tabs: { key: TabKey; label: string; icon: React.ElementType }[] = [
  { key: 'profile', label: 'Profile', icon: UserRound }, { key: 'appointments', label: 'Appointments', icon: CalendarDays }, { key: 'vitals', label: 'Vitals / Triage', icon: Activity }, { key: 'encounters', label: 'Encounters', icon: Stethoscope }, { key: 'labs', label: 'Lab Orders', icon: FlaskConical }, { key: 'prescriptions', label: 'Prescriptions', icon: Pill }, { key: 'billing', label: 'Billing', icon: CreditCard }, { key: 'documents', label: 'Documents', icon: FileText }, { key: 'admission', label: 'Admission', icon: BedDouble },
];
const administrativeRoles = new Set(['admin', 'it_admin', 'system_superuser']);
const editRoles = new Set(['admin', 'it_admin', 'system_superuser', 'practitioner', 'nurse', 'midwife', 'front_desk']);
const clinicalRoles = new Set(['admin', 'it_admin', 'system_superuser', 'practitioner', 'nurse', 'midwife']);
const clinicalHistoryRoles = new Set(['admin', 'it_admin', 'system_superuser', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'lab_technician', 'pharmacist']);
const billingRoles = new Set(['admin', 'accountant', 'front_desk']);
function formatDate(value?: string | null) { return value ? new Date(value).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : '—'; }
function Section({ title, children, action }: { title: string; children: React.ReactNode; action?: React.ReactNode }) { return <section className="card-medical p-5 space-y-4"><div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"><h2 className="text-lg font-semibold">{title}</h2>{action}</div>{children}</section>; }
function EmptyState({ label }: { label: string }) { return <div className="rounded-2xl border border-dashed border-border p-8 text-center"><FileText className="mx-auto h-7 w-7 text-muted-foreground"/><p className="mt-2 text-sm font-medium">No {label} recorded yet</p><p className="mt-1 text-xs text-muted-foreground">When this information becomes available, it will appear here.</p></div>; }
function SectionUnavailable({ label, onRetry }: { label: string; onRetry: () => void }) { return <div className="rounded-2xl border border-warning/30 bg-warning/5 p-6 text-center" role="alert"><p className="font-medium">Unable to load {label}</p><p className="mt-1 text-sm text-muted-foreground">The records have not been confirmed as empty. Retry to load this section.</p><button type="button" onClick={onRetry} className="btn-secondary mt-3 inline-flex items-center gap-2"><RefreshCw className="h-4 w-4" />Retry section</button></div>; }

export default function PatientHub() {
  const { patientId } = useParams<{ patientId: string }>(); const navigate = useNavigate(); const [searchParams] = useSearchParams(); const currentAdmissionId = searchParams.get('admission'); const { user } = useAuth();
  const [patient, setPatient] = useState<any>(null); const [patientLoadError, setPatientLoadError] = useState(''); const [activeTab, setActiveTab] = useState<TabKey>(() => searchParams.get('vitals') === '1' ? 'vitals' : 'profile'); const [loading, setLoading] = useState(true); const [historyLoading, setHistoryLoading] = useState(false); const [historyError, setHistoryError] = useState(''); const [failedSections, setFailedSections] = useState<string[]>([]); const [refreshKey, setRefreshKey] = useState(0); const [rows, setRows] = useState<Record<string, any[]>>({});
  const roleSet = useMemo(() => new Set(user?.roles ?? (user ? [user.role] : [])), [user?.roles, user?.role]); const canEdit = [...roleSet].some((role) => editRoles.has(role)); const canClinicalWrite = [...roleSet].some((role) => clinicalRoles.has(role)); const canClinicalHistory = [...roleSet].some((role) => clinicalHistoryRoles.has(role)); const canBill = [...roleSet].some((role) => billingRoles.has(role)); const canManageInsurance = [...roleSet].some((role) => administrativeRoles.has(role));
  const loadPatient = useCallback(async () => { if (!patientId) return; setLoading(true); setPatientLoadError(''); try { const data = await getPatientById(patientId); if (!data) { setPatient(null); setPatientLoadError('This patient record was not found in your active facility, or your account does not have permission to view it. Verify the hospital ID and active facility. If TEST MODE is active, use a patient registered under TEST-0001; records assigned to another facility remain blocked. If the record has no verified facility attribution, an administrator must reconcile it before it can be opened.'); return; } setPatient(data); } catch (error: any) { const message = String(error?.message ?? 'Unable to load patient record.'); setPatient(null); setPatientLoadError(message.toLowerCase().includes('active facility') ? 'Your account has no active facility context. Patient records are facility-scoped. Ask an administrator to assign your facility or select an active facility, then reopen this record.' : message.toLowerCase().includes('facility context') ? 'This patient belongs to a different facility context. Switch to the patient’s facility, then reopen the record. Test-mode accounts are restricted to the test facility.' : message.toLowerCase().includes('facility attribution is unresolved') ? 'This patient has no verified facility attribution. An administrator or IT administrator must reconcile the record before it can be opened.' : message); } finally { setLoading(false); } }, [navigate, patientId]);
  const loadHistory = useCallback(async () => {
    if (!patientId) return; const db = supabase as any; setHistoryLoading(true); setHistoryError(''); setFailedSections([]);
    if (currentAdmissionId) {
      const { data, error } = await db.rpc('get_patient_current_treatment_snapshot', { _patient_id: patientId, _admission_id: currentAdmissionId });
      if (error) {
        setRows({}); setFailedSections(['clinical', 'admissions']); setHistoryError(error.message ?? 'Unable to load the current treatment context.'); toast.error(error.message ?? 'Unable to load the current treatment context.');
      } else {
        const snapshot = data ?? {};
        setRows({
          admissions: snapshot.admission ? [snapshot.admission] : [],
          vitals: snapshot.vitals ?? [],
          encounters: snapshot.encounters ?? [],
          labs: snapshot.labs ?? [],
          prescriptions: snapshot.prescriptions ?? [],
          documents: [],
          appointments: [],
          invoices: [],
          nursing_notes: snapshot.nursing_notes ?? [],
        });
      }
      setHistoryLoading(false); return;
    }
    const specs = [
      ['appointments', db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 })],
      ...(canClinicalHistory ? [['clinical', db.rpc('get_patient_hub_clinical_snapshot', { _patient_id: patientId })]] : []),
      ...([...roleSet].some((role) => billingRoles.has(role)) ? [['invoices', db.rpc('get_patient_invoices', { _patient_id: patientId, _limit: 100 })]] : []),
      ...([...roleSet].some((role) => clinicalRoles.has(role) || role === 'system_superuser') ? [['admissions', db.rpc('get_patient_admission_history', { _patient_id: patientId })]] : []),
    ];
    const settled = await Promise.allSettled(specs.map(async ([key, request]) => [key, await request] as const)); const nextRows: Record<string, any[]> = {};
    const failed: string[] = [];
    settled.forEach((item, index) => { const key = specs[index][0] as string; if (item.status === 'fulfilled') { const response = item.value[1]; if (response.error) failed.push(key); else if (key === 'clinical') { const snapshot = response.data ?? {}; nextRows.vitals = snapshot.vitals ?? []; nextRows.encounters = snapshot.encounters ?? []; nextRows.labs = snapshot.labs ?? []; nextRows.prescriptions = snapshot.prescriptions ?? []; nextRows.documents = snapshot.documents ?? []; } else nextRows[key] = response.data ?? []; } else failed.push(key); });
    setRows(nextRows); setFailedSections(failed); if (failed.length) { const message = `Some sections could not be loaded: ${failed.join(', ')}.`; setHistoryError(message); toast.warning(`${message} Other sections remain available.`); } setHistoryLoading(false);
  }, [patientId, roleSet, canClinicalHistory, currentAdmissionId]);
  useEffect(() => { void loadPatient(); }, [loadPatient]); useEffect(() => { if (patient) void loadHistory(); }, [loadHistory, patient, refreshKey]);
  const tabCounts = useMemo<Record<TabKey, number>>(() => ({ profile: 1, appointments: rows.appointments?.length ?? 0, vitals: rows.vitals?.length ?? 0, encounters: rows.encounters?.length ?? 0, labs: rows.labs?.length ?? 0, prescriptions: rows.prescriptions?.length ?? 0, billing: rows.invoices?.length ?? 0, documents: rows.documents?.length ?? 0, admission: rows.admissions?.length ?? 0 }), [rows]);
  const refresh = () => setRefreshKey((v) => v + 1);
  if (loading) return <div className="p-8 text-sm text-muted-foreground">Loading patient record…</div>;
  if (!patient) return <div className="p-8 space-y-4"><p className="font-medium">{patientLoadError ? 'Unable to open patient record' : 'Patient record not found.'}</p>{patientLoadError && <p role="alert" className="max-w-2xl text-sm text-muted-foreground">{patientLoadError}</p>}<Link to="/patients" className="btn-secondary inline-flex">Back to search</Link></div>;
  return <div className="space-y-5 animate-fade-in pb-6">
    <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between"><div className="flex items-center gap-3"><button type="button" onClick={() => navigate('/patients')} className="p-2 rounded-lg hover:bg-muted" aria-label="Back to patient search"><ArrowLeft className="w-5 h-5" /></button><PatientAvatar name={`${patient.first_name} ${patient.last_name}`} size="lg" /><div><h1 className="text-2xl font-heading font-bold">{patient.first_name} {patient.last_name}</h1><div className="mt-1 flex flex-wrap items-center gap-2 text-sm text-muted-foreground"><span>Patient code: {patient.patient_code}</span><span aria-hidden="true">·</span><span className="capitalize">{patient.status || 'active'}</span></div></div></div><RefreshButton onClick={refresh} loading={historyLoading} label="Refresh patient record" /></div>
    <div className="overflow-x-auto rounded-2xl border border-border bg-card"><div className="flex min-w-max gap-1 p-2" role="tablist" aria-label="Patient record sections">{tabs.map((tab) => { const Icon = tab.icon; return <button key={tab.key} onClick={() => setActiveTab(tab.key)} className={`inline-flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-medium whitespace-nowrap ${activeTab === tab.key ? 'bg-primary text-primary-foreground' : 'hover:bg-muted text-muted-foreground'}`} role="tab" aria-selected={activeTab === tab.key} aria-controls={`patient-tab-${tab.key}`} tabIndex={activeTab === tab.key ? 0 : -1} onKeyDown={(event) => { if (event.key === 'ArrowRight' || event.key === 'ArrowDown') { event.preventDefault(); setActiveTab(tabs[(tabs.findIndex((item) => item.key === activeTab) + 1) % tabs.length].key); } if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') { event.preventDefault(); setActiveTab(tabs[(tabs.findIndex((item) => item.key === activeTab) - 1 + tabs.length) % tabs.length].key); } }} ><Icon className="w-4 h-4" />{tab.label}<span className={`inline-flex min-w-5 items-center justify-center rounded-full px-1.5 py-0.5 text-[10px] ${activeTab === tab.key ? 'bg-white/20 text-white ring-1 ring-white/20' : tabCounts[tab.key] > 0 ? 'bg-primary/15 text-primary' : 'bg-muted text-muted-foreground'}`}>{tabCounts[tab.key]}</span></button>; })}</div></div>
    {historyError && <div role="status" className="rounded-2xl border border-warning/30 bg-warning/5 p-3 text-sm text-foreground">{historyError} Use Refresh record to try again.</div>}<div id={`patient-tab-${activeTab}`} role="tabpanel" aria-labelledby={`patient-tab-${activeTab}`} tabIndex={0} className="outline-none">{activeTab === 'profile' && <ProfileTab patient={patient} canEdit={canEdit} canManageInsurance={canManageInsurance} onSaved={(next) => setPatient(next)} />}
    {activeTab === 'appointments' && (failedSections.includes('appointments') ? <SectionUnavailable label="appointment history" onRetry={refresh} /> : <AppointmentsTab patientId={patient.id} rows={rows.appointments ?? []} canWrite={canClinicalWrite} isPatient={roleSet.has('patient')} onSaved={refresh} />)}
    {activeTab === 'vitals' && (failedSections.includes('clinical') ? <SectionUnavailable label="vital-sign history" onRetry={refresh} /> : <VitalsTab patientId={patient.id} rows={rows.vitals ?? []} canWrite={canClinicalWrite} onSaved={refresh} />)}
    {activeTab === 'encounters' && (failedSections.includes('clinical') ? <SectionUnavailable label="clinical encounter history" onRetry={refresh} /> : <EncountersTab patientId={patient.id} rows={rows.encounters ?? []} canWrite={canClinicalWrite} onSaved={refresh} />)}
    {activeTab === 'labs' && (failedSections.includes('clinical') ? <SectionUnavailable label="laboratory history" onRetry={refresh} /> : <LabsTab patientId={patient.id} rows={rows.labs ?? []} canWrite={canClinicalWrite} onSaved={refresh} />)}
    {activeTab === 'prescriptions' && (failedSections.includes('clinical') ? <SectionUnavailable label="prescription history" onRetry={refresh} /> : <PrescriptionsTab patientId={patient.id} encounterId={rows.encounters?.[0]?.id ?? null} rows={rows.prescriptions ?? []} canWrite={canClinicalWrite} onSaved={refresh} />)}
    {activeTab === 'billing' && (failedSections.includes('invoices') ? <SectionUnavailable label="billing history" onRetry={refresh} /> : <BillingTab patientId={patient.id} rows={rows.invoices ?? []} canWrite={canBill} onSaved={refresh} />)}
    {activeTab === 'documents' && (failedSections.includes('clinical') ? <SectionUnavailable label="patient document history" onRetry={refresh} /> : <DocumentsTab patientId={patient.id} rows={rows.documents ?? []} canWrite={canEdit} onSaved={refresh} />)}
    {activeTab === 'admission' && (failedSections.includes('admissions') ? <SectionUnavailable label="admission history" onRetry={refresh} /> : <AdmissionTab patientId={patient.id} rows={rows.admissions ?? []} canWrite={canClinicalWrite} onSaved={refresh} />)}</div>
  </div>;
}

function ProfileTab({ patient, canEdit, canManageInsurance, onSaved }: { patient: any; canEdit: boolean; canManageInsurance: boolean; onSaved: (patient: any) => void }) {
  const initialForm = { first_name: patient.first_name ?? '', last_name: patient.last_name ?? '', date_of_birth: patient.date_of_birth ?? '', gender: patient.gender ?? '', phone: patient.phone ?? '', email: patient.email ?? '', address: patient.address ?? '', city: patient.city ?? '', ghana_card_number: patient.ghana_card_number ?? '', blood_group: patient.blood_group ?? '', genotype: patient.genotype ?? '', allergies: patient.allergies ?? '', chronic_conditions: patient.chronic_conditions ?? '', insurance_provider: patient.insurance_provider ?? '', insurance_number: patient.insurance_number ?? '', insurance_group_number: patient.insurance_group_number ?? '', insurance_expiry: patient.insurance_expiry ?? '', insurance_company_id: patient.insurance_company_id ?? '', emergency_contact_name: patient.emergency_contact_name ?? '', emergency_contact_phone: patient.emergency_contact_phone ?? '', emergency_contact_relation: patient.emergency_contact_relation ?? '' };
  const [form, setForm] = useState(initialForm);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [insurers, setInsurers] = useState<Array<{id:string;code:string;name:string}>>([]);
  const [insurersLoading, setInsurersLoading] = useState(false);
  const update = (key: string, value: string) => { setForm((c) => ({ ...c, [key]: value })); setDirty(true); };
  useEffect(() => {
    if (!canManageInsurance) return;
    let active = true;
    setInsurersLoading(true);
    void (async () => {
      const { data, error } = await (supabase as any).rpc('list_insurance_companies', { _include_inactive: false });
      if (!active) return;
      setInsurersLoading(false);
      if (error) {
        toast.error(error.message ?? 'Unable to load insurance companies');
        return;
      }
      setInsurers((data ?? []) as Array<{id:string;code:string;name:string}>);
    })();
    return () => { active = false; };
  }, [canManageInsurance]);
  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (!dirty) { toast.info('No patient changes to save.'); return; }
    setSaving(true);
    try {
      const updatePayload = {
        firstName: form.first_name,
        lastName: form.last_name,
        dateOfBirth: form.date_of_birth,
        gender: form.gender,
        phone: form.phone,
        email: form.email,
        address: form.address,
        city: form.city,
        ghanaCardNumber: form.ghana_card_number,
        bloodType: form.blood_group,
        genotype: form.genotype,
        allergies: form.allergies,
        chronicConditions: form.chronic_conditions,
        insuranceProvider: form.insurance_provider,
        insuranceNumber: form.insurance_number,
        insuranceGroupNumber: form.insurance_group_number,
        insuranceExpiry: form.insurance_expiry,
        emergencyContact: { name: form.emergency_contact_name, phone: form.emergency_contact_phone, relationship: form.emergency_contact_relation },
      };
      const updated = await updatePatient(patient.id, updatePayload as any);
      let nextPatient = { ...patient, ...form };
      if (canManageInsurance && form.insurance_company_id !== (patient.insurance_company_id ?? '')) {
        const { data: linked, error: insurerError } = await (supabase as any).rpc('set_patient_insurance_company', {
          _patient_id: patient.id,
          _insurance_company_id: form.insurance_company_id || null,
        });
        if (insurerError) throw insurerError;
        nextPatient = { ...nextPatient, ...(linked ?? {}), insurance_company_id: form.insurance_company_id || null };
      } else {
        nextPatient = { ...nextPatient, ...(updated?.patient ?? {}) };
      }
      onSaved(nextPatient);
      setDirty(false);
      toast.success('Patient record updated. The change was added to the audit trail.');
    } catch (error: any) {
      toast.error(error.message ?? 'Could not update patient record');
    } finally {
      setSaving(false);
    }
  };
  const fields = [['first_name','First name'],['last_name','Last name'],['date_of_birth','Date of birth'],['phone','Phone'],['email','Email'],['address','Address'],['city','City'],['ghana_card_number','Ghana Card / national identifier'],['blood_group','Blood group'],['genotype','Genotype'],['insurance_provider','Insurance provider'],['insurance_number','Insurance policy number'],['insurance_group_number','Insurance group number'],['insurance_expiry','Insurance expiry'],['emergency_contact_name','Emergency contact'],['emergency_contact_phone','Emergency phone'],['emergency_contact_relation','Emergency relationship']] as const;
  return <Section title="Patient demographic and administrative record"><form onSubmit={save} className="space-y-5"><div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{fields.map(([key,label]) => <label key={key} className="space-y-1 text-sm"><span className="font-medium">{label}</span><input type={key.includes('date') || key === 'insurance_expiry' ? 'date' : key === 'email' ? 'email' : key.includes('phone') ? 'tel' : 'text'} value={form[key] ?? ''} onChange={(e) => update(key,e.target.value)} disabled={!canEdit} className="input-medical w-full" /></label>)}
  <label className="space-y-1 text-sm"><span className="font-medium">Gender</span><select value={form.gender} onChange={(e)=>update('gender',e.target.value)} disabled={!canEdit} className="input-medical w-full"><option value="">Not recorded</option><option value="male">Male</option><option value="female">Female</option><option value="other">Other</option></select></label>
  {canManageInsurance && <label className="space-y-1 text-sm"><span className="font-medium">Canonical insurance company</span><select value={form.insurance_company_id} onChange={(e)=>update('insurance_company_id',e.target.value)} disabled={!canEdit || insurersLoading} className="input-medical w-full"><option value="">No canonical insurer linked</option>{insurers.map((company)=><option key={company.id} value={company.id}>{company.name} ({company.code})</option>)}</select><span className="text-xs text-muted-foreground">{insurersLoading ? 'Loading configured insurers…' : insurers.length ? 'Authoritative payer used by claims and billing reconciliation.' : 'No active canonical insurers are configured yet.'}</span></label>}
  <label className="space-y-1 text-sm sm:col-span-2"><span className="font-medium">Allergies</span><textarea value={form.allergies} onChange={(e)=>update('allergies',e.target.value)} disabled={!canEdit} className="input-medical min-h-20 w-full" /></label><label className="space-y-1 text-sm sm:col-span-2"><span className="font-medium">Chronic conditions</span><textarea value={form.chronic_conditions} onChange={(e)=>update('chronic_conditions',e.target.value)} disabled={!canEdit} className="input-medical min-h-20 w-full" /></label></div>{canEdit ? <div className="flex flex-wrap items-center gap-3"><button type="submit" disabled={saving || !dirty} className="btn-primary inline-flex items-center gap-2"><Save className="w-4 h-4" />{saving ? 'Saving…':'Save patient changes'}</button>{dirty && !saving && <span className="text-xs text-muted-foreground">Unsaved changes</span>}</div> : <p className="text-sm text-muted-foreground">Your role has read-only access to patient demographics.</p>}</form></Section>;
}
function AppointmentsTab({ patientId, rows, canWrite, isPatient, onSaved }: any) { const [form,setForm]=useState({scheduled_at:'',department:'',reason:''}); const submit=async(e:FormEvent)=>{e.preventDefault();const {error}=isPatient ? await(supabase as any).rpc('create_patient_appointment',{_patient_id:patientId,_scheduled_at:new Date(form.scheduled_at).toISOString(),_department:form.department||null,_reason:form.reason||null}) : await(supabase as any).rpc('create_appointment_workflow',{_patient_id:patientId,_scheduled_at:new Date(form.scheduled_at).toISOString(),_department:form.department||'Clinical Consultation',_reason:form.reason||null,_consultation_type:form.department||'Clinical Consultation',_practitioner_id:null});if(error)return toast.error(error.message);setForm({scheduled_at:'',department:'',reason:''});toast.success('Appointment added');onSaved();};return <div className="space-y-5"><Section title="Appointment history">{rows.length?<div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Scheduled</th><th className="p-2">Department</th><th className="p-2">Reason</th><th className="p-2">Status</th></tr></thead><tbody>{rows.map((r:any)=><tr key={r.id} className="border-b"><td className="p-2">{formatDate(r.scheduled_at)}</td><td className="p-2">{r.department||'—'}</td><td className="p-2">{r.reason||'—'}</td><td className="p-2 capitalize">{r.status}</td></tr>)}</tbody></table></div>:<EmptyState label="appointments"/>}</Section>{canWrite&&<Section title="Add appointment"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-3"><input required type="datetime-local" value={form.scheduled_at} onChange={e=>setForm({...form,scheduled_at:e.target.value})} className="input-medical"/><input placeholder="Department" value={form.department} onChange={e=>setForm({...form,department:e.target.value})} className="input-medical"/><input placeholder="Reason" value={form.reason} onChange={e=>setForm({...form,reason:e.target.value})} className="input-medical"/><button className="btn-primary sm:col-span-3">Create appointment</button></form></Section>}</div>; }

function VitalsTab({ patientId, canWrite, onSaved }: any) {
  const scopedPatientId = normalizePatientId(patientId);
  const [records, setRecords] = useState<TriageHistoryRecord[]>([]);
  const [loading, setLoading] = useState(Boolean(scopedPatientId));
  const [error, setError] = useState('');
  const [filter, setFilter] = useState<TriageParameter>('all');
  const [showForm, setShowForm] = useState(false);

  const load = useCallback(async () => {
    if (!scopedPatientId) {
      setRecords([]);
      setLoading(false);
      setError('');
      return;
    }
    setLoading(true);
    setError('');
    const { data, error: requestError } = await (supabase as any).rpc('get_patient_triage_history', {
      _patient_id: scopedPatientId,
      _limit: 200,
    });
    if (requestError) {
      setRecords([]);
      setError('Unable to load triage history. Retry.');
    } else {
      setRecords((data ?? []) as TriageHistoryRecord[]);
    }
    setLoading(false);
  }, [scopedPatientId]);

  useEffect(() => { void load(); }, [load]);

  const visible = useMemo(() => selectTriageParameter(records, filter), [records, filter]);

  if (!scopedPatientId) {
    return <Section title="Vitals / Triage"><div className="rounded-2xl border border-dashed border-border p-8 text-center" role="status"><Activity className="mx-auto h-7 w-7 text-muted-foreground" /><p className="mt-2 font-medium">No patient selected</p><p className="mt-1 text-sm text-muted-foreground">Open a patient record before viewing triage history.</p></div></Section>;
  }

  return <div className="space-y-5">
    <Section title="Vitals / Triage history" action={canWrite ? <button type="button" onClick={() => setShowForm((value) => !value)} className="btn-primary">{showForm ? 'Close form' : 'Add Record'}</button> : undefined}>
      {showForm && canWrite && <div className="mb-5 rounded-2xl border border-primary/20 bg-primary/5 p-4"><TriageRecordForm patientId={scopedPatientId} onSaved={() => { setShowForm(false); onSaved?.(); void load(); }} onCancel={() => setShowForm(false)} /></div>}
      {loading && <div className="space-y-3" role="status" aria-label="Loading triage history"><div className="h-5 w-40 animate-pulse rounded bg-muted" /><div className="h-80 animate-pulse rounded-xl bg-muted" /><div className="h-20 animate-pulse rounded-xl bg-muted" /></div>}
      {!loading && error && <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm" role="alert"><p className="font-medium">{error}</p><button type="button" onClick={() => void load()} className="btn-secondary mt-3">Retry</button></div>}
      {!loading && !error && records.length === 0 && <div className="rounded-2xl border border-dashed border-border p-8 text-center" role="status"><Activity className="mx-auto h-7 w-7 text-muted-foreground" /><p className="mt-2 font-medium">No triage records yet for this patient</p><p className="mt-1 text-sm text-muted-foreground">Add a record when the patient's measured vital signs are available.</p></div>}
      {!loading && !error && records.length > 0 && <>
        <TriageHistoryChart records={visible} parameter={filter} />
        <nav aria-label="Triage parameter filters" className="mt-2 border-t pt-3">
          <div className="flex flex-wrap items-center justify-center gap-x-2 gap-y-2" role="list">
            {(['all', 'temp', 'bp', 'bmi', 'spo2'] as TriageParameter[]).map((item) => {
              const label = item === 'all' ? 'All' : item === 'temp' ? 'Temp' : item === 'bp' ? 'BP' : item === 'bmi' ? 'BMI' : 'SpO2';
              const selected = filter === item;
              const marker = item === 'all' ? (
                <span className="flex items-center gap-0.5" aria-hidden="true">
                  <span className="h-2 w-2 rounded-full bg-[hsl(var(--warning))]" />
                  <span className="h-2 w-2 rounded-full bg-[hsl(var(--destructive))]" />
                  <span className="h-2 w-2 rounded-full bg-[hsl(var(--success))]" />
                  <span className="h-2 w-2 rounded-full bg-[hsl(var(--info))]" />
                </span>
              ) : item === 'temp' ? (
                <span className="h-0.5 w-5 rounded-full bg-[hsl(var(--warning))]" aria-hidden="true" />
              ) : item === 'bp' ? (
                <span className="flex items-center gap-0.5" aria-hidden="true">
                  <span className="h-0.5 w-4 rounded-full bg-[hsl(var(--destructive))]" />
                  <span className="h-0.5 w-4 rounded-full bg-[hsl(var(--primary))]" />
                </span>
              ) : item === 'bmi' ? (
                <span className="h-0.5 w-5 rounded-full bg-[hsl(var(--success))]" aria-hidden="true" />
              ) : (
                <span className="h-0.5 w-5 rounded-full bg-[hsl(var(--info))]" aria-hidden="true" />
              );
              return (
                <span key={item} role="listitem" className="flex items-center">
                  <button
                    type="button"
                    onClick={() => setFilter(item)}
                    aria-pressed={selected}
                    className={`inline-flex min-h-9 items-center gap-2 rounded-lg px-3 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${selected ? 'bg-muted text-foreground ring-1 ring-border' : 'text-muted-foreground hover:bg-muted/60 hover:text-foreground'}`}
                  >
                    {marker}
                    <span>{label}</span>
                  </button>
                  {item !== 'spo2' && <span className="mx-1 text-border" aria-hidden="true">|</span>}
                </span>
              );
            })}
          </div>
          <p className="mt-2 text-center text-xs text-muted-foreground">Select a parameter to isolate its trend; the markers match the plotted series.</p>
        </nav>
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-sm">
            <thead><tr className="border-b text-left"><th className="p-2">Recorded</th><th className="p-2">BP</th><th className="p-2">Temp</th><th className="p-2">BMI</th><th className="p-2">SpO₂</th></tr></thead>
            <tbody>{records.map((record) => <tr key={record.id} className="border-b last:border-0"><td className="p-2">{formatDate(record.recorded_at)}</td><td className="p-2">{record.systolic !== null || record.diastolic !== null ? `${record.systolic ?? '—'}/${record.diastolic ?? '—'}` : '—'}</td><td className="p-2">{record.temperature ?? '—'}</td><td className="p-2">{record.bmi ?? '—'}</td><td className="p-2">{record.oxygen_saturation ?? '—'}</td></tr>)}</tbody>
          </table>
        </div>
      </>}
    </Section>
  </div>;
}

function EncountersTab({ patientId, rows, canWrite, onSaved }: any) {
  const navigate = useNavigate();
  const [form, setForm] = useState({ chief_complaint: '', notes: '' });
  const [saving, setSaving] = useState(false);

  const openEncounter = (encounterId?: string) => {
    const query = encounterId ? `?patient=${encodeURIComponent(patientId)}&encounter=${encodeURIComponent(encounterId)}` : `?patient=${encodeURIComponent(patientId)}`;
    navigate(`/encounters${query}`);
  };

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!form.chief_complaint.trim()) {
      toast.error('Chief complaint / presenting problem is required.');
      return;
    }
    setSaving(true);
    try {
      const { data, error } = await (supabase as any).rpc('create_encounter_workflow', {
        _patient_id: patientId,
        _symptoms: form.chief_complaint.trim(),
        _clerking_notes: form.notes.trim() || null,
      });
      if (error) throw error;
      setForm({ chief_complaint: '', notes: '' });
      toast.success(`Encounter ${data?.id ? 'created' : 'started'} as a draft. Continue clerking, diagnosis and treatment in the Encounter workspace.`);
      onSaved();
      if (data?.id) openEncounter(data.id);
    } catch (error: any) {
      toast.error(error.message ?? 'Could not start encounter');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-5">
      <Section
        title="Encounter history"
        action={
          <button type="button" onClick={() => openEncounter()} className="btn-secondary inline-flex items-center gap-2">
            <Stethoscope className="w-4 h-4" />
            Open Encounter workspace
          </button>
        }
      >
        {rows.length ? (
          <div className="space-y-3">
            {rows.map((r: any) => (
              <article key={r.id} className="rounded-xl border p-4 hover:border-primary/40 transition-colors">
                <button type="button" onClick={() => openEncounter(r.id)} className="w-full text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-lg">
                  <div className="flex flex-wrap justify-between gap-2">
                    <strong>{r.chief_complaint || r.symptoms || 'Clinical encounter'}</strong>
                    <span className="text-xs text-muted-foreground">{formatDate(r.created_at)}</span>
                  </div>
                  <div className="mt-2 grid gap-2 sm:grid-cols-3 text-xs">
                    <span><b>Status:</b> <span className="capitalize">{r.status || 'draft'}</span></span>
                    <span><b>Principal diagnosis:</b> {r.principal_diagnosis || 'Not yet recorded'}</span>
                    <span><b>Plan:</b> {r.treatment_plan || 'Not yet recorded'}</span>
                  </div>
                  <p className="mt-2 text-sm text-muted-foreground whitespace-pre-wrap">{r.clerking_notes || r.notes || 'No clerking notes recorded.'}</p>
                </button>
                {r.status !== 'completed' && r.status !== 'cancelled' && (
                  <div className="mt-3 flex flex-wrap items-center gap-2 border-t pt-3">
                    <span className="text-xs text-muted-foreground">Draft documentation can be resumed in the full encounter workspace.</span>
                    <button type="button" onClick={() => openEncounter(r.id)} className="btn-primary inline-flex items-center gap-2">
                      <Stethoscope className="w-4 h-4" />
                      Continue encounter
                    </button>
                  </div>
                )}
              </article>
            ))}
          </div>
        ) : (
          <EmptyState label="encounters" />
        )}
      </Section>

      {canWrite && (
        <Section title="Start encounter">
          <form onSubmit={submit} className="space-y-4">
            <div>
              <label className="text-sm font-medium">Chief complaint / presenting problem</label>
              <input
                required
                placeholder="What brings the patient for care?"
                value={form.chief_complaint}
                onChange={e => setForm({ ...form, chief_complaint: e.target.value })}
                className="input-medical mt-1 w-full"
              />
            </div>
            <div>
              <label className="text-sm font-medium">Initial clerking notes <span className="font-normal text-muted-foreground">(optional)</span></label>
              <textarea
                placeholder="Initial history or clinical notes"
                value={form.notes}
                onChange={e => setForm({ ...form, notes: e.target.value })}
                className="input-medical mt-1 min-h-24 w-full"
              />
            </div>
            <div className="flex flex-wrap items-center gap-3">
              <button type="submit" disabled={saving} className="btn-primary inline-flex items-center gap-2">
                <Stethoscope className="w-4 h-4" />
                {saving ? 'Starting…' : 'Start draft encounter'}
              </button>
              <span className="text-xs text-muted-foreground">The draft remains server-authorized and opens in the full workflow so diagnosis, prescriptions, treatment and finalization stay attached to the same encounter.</span>
            </div>
          </form>
        </Section>
      )}
    </div>
  );
}

function LabsTab({ patientId, rows, canWrite, onSaved }: any) { const [form,setForm]=useState({test_name:'',clinical_notes:''}); const submit=async(e:FormEvent)=>{e.preventDefault();const {data,error}=await(supabase as any).rpc('create_lab_order_with_payment_gate',{_patient_id:patientId,_test_name:form.test_name,_test_category:'general',_priority:'routine',_clinical_notes:form.clinical_notes||null,_amount:0});if(error)return toast.error(error.message);setForm({test_name:'',clinical_notes:''});toast.success(`Lab order ${data?.lab_order_id??''} created`);onSaved();};return <div className="space-y-5"><Section title="Laboratory orders">{rows.length?<div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Created</th><th className="p-2">Test</th><th className="p-2">Status</th><th className="p-2">Payment</th></tr></thead><tbody>{rows.map((r:any)=><tr key={r.id} className="border-b"><td className="p-2">{formatDate(r.created_at)}</td><td className="p-2">{r.test_name||r.test_type||'Laboratory test'}</td><td className="p-2 capitalize">{r.status||'—'}</td><td className="p-2 capitalize">{r.payment_status||'—'}</td></tr>)}</tbody></table></div>:<EmptyState label="lab orders"/>}</Section>{canWrite&&<Section title="Create lab order"><form onSubmit={submit} className="space-y-4"><input required placeholder="Test name" value={form.test_name} onChange={e=>setForm({...form,test_name:e.target.value})} className="input-medical w-full"/><textarea placeholder="Clinical notes / indication" value={form.clinical_notes} onChange={e=>setForm({...form,clinical_notes:e.target.value})} className="input-medical min-h-20 w-full"/><button className="btn-primary">Create lab order</button></form></Section>}</div>; }

function PrescriptionsTab({ patientId, encounterId, rows, canWrite, onSaved }: any) { const [form,setForm]=useState({medication_name:'',dose:'',frequency:'',duration:''}); const submit=async(e:FormEvent)=>{e.preventDefault();if(!encounterId)return toast.error('Create or select a clinical encounter before prescribing.');const {data,error}=await(supabase as any).rpc('create_encounter_prescription',{_encounter_id:encounterId,_medication:form.medication_name,_dosage:form.dose,_frequency:form.frequency,_duration:form.duration||null});if(error)return toast.error(error.message);setForm({medication_name:'',dose:'',frequency:'',duration:''});toast.success(`Prescription ${data?.prescription_id??''} created`);onSaved();};return <div className="space-y-5"><Section title="Prescription history">{rows.length?<div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Created</th><th className="p-2">Medication</th><th className="p-2">Dose</th><th className="p-2">Frequency</th><th className="p-2">Status</th></tr></thead><tbody>{rows.map((r:any)=><tr key={r.id} className="border-b"><td className="p-2">{formatDate(r.created_at)}</td><td className="p-2">{r.medication_name||r.medication}</td><td className="p-2">{r.dose||'—'}</td><td className="p-2">{r.frequency||'—'}</td><td className="p-2 capitalize">{r.status||'—'}</td></tr>)}</tbody></table></div>:<EmptyState label="prescriptions"/>}</Section>{canWrite&&<Section title="Create prescription"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-2"><input required placeholder="Medication" value={form.medication_name} onChange={e=>setForm({...form,medication_name:e.target.value})} className="input-medical"/><input required placeholder="Dose" value={form.dose} onChange={e=>setForm({...form,dose:e.target.value})} className="input-medical"/><input required placeholder="Frequency" value={form.frequency} onChange={e=>setForm({...form,frequency:e.target.value})} className="input-medical"/><input placeholder="Duration" value={form.duration} onChange={e=>setForm({...form,duration:e.target.value})} className="input-medical"/><button className="btn-primary sm:col-span-2">Create prescription</button></form></Section>}</div>; }

function BillingTab({ patientId, rows, canWrite, onSaved }: any) { return <div className="space-y-5"><Section title="Billing history">{rows.length?<div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Invoice</th><th className="p-2">Date</th><th className="p-2">Status</th><th className="p-2">Total</th></tr></thead><tbody>{rows.map((r:any)=><tr key={r.id} className="border-b"><td className="p-2">{r.invoice_number||r.id}</td><td className="p-2">{formatDate(r.created_at)}</td><td className="p-2 capitalize">{r.status}</td><td className="p-2">{r.total_amount??r.amount??'—'}</td></tr>)}</tbody></table></div>:<EmptyState label="invoices"/>}</Section><div className="text-sm text-muted-foreground">Use the Billing module for bill preparation, item-level payment and service-order release. Patient Hub does not duplicate payment processing.</div></div>; }

function DocumentsTab({ patientId, rows, canWrite, onSaved }: any) { const [form,setForm]=useState({document_type:'',file_url:'',notes:''}); const submit=async(e:FormEvent)=>{e.preventDefault();const {error}=await(supabase as any).rpc('create_patient_document',{_patient_id:patientId,_document_type:form.document_type,_file_url:form.file_url,_notes:form.notes||null});if(error)return toast.error(error.message);setForm({document_type:'',file_url:'',notes:''});toast.success('Document metadata recorded');onSaved();};return <div className="space-y-5"><Section title="Patient documents">{rows.length?<div className="space-y-2">{rows.map((r:any)=><div key={r.id} className="rounded-xl border p-4"><div className="flex justify-between gap-3"><strong>{r.document_type||'Document'}</strong><span className="text-xs text-muted-foreground">{formatDate(r.created_at)}</span></div><p className="text-sm text-muted-foreground mt-1">{r.notes||'No notes.'}</p></div>)}</div>:<EmptyState label="documents"/>}</Section>{canWrite&&<Section title="Add document record"><form onSubmit={submit} className="space-y-4"><input required placeholder="Document type" value={form.document_type} onChange={e=>setForm({...form,document_type:e.target.value})} className="input-medical w-full"/><input required placeholder="Private storage path / file reference" value={form.file_url} onChange={e=>setForm({...form,file_url:e.target.value})} className="input-medical w-full"/><textarea placeholder="Notes" value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})} className="input-medical min-h-20 w-full"/><button className="btn-primary">Save document record</button></form></Section>}</div>; }

function AdmissionTab({ patientId, rows, canWrite, onSaved }: any) { const [form,setForm]=useState({reason:'',ward:'',bed_id:''}); const submit=async(e:FormEvent)=>{e.preventDefault();const {data,error}=await(supabase as any).rpc('create_admission_workflow',{_patient_id:patientId,_ward:form.ward||null,_bed:form.bed_id||null,_reason:form.reason});if(error)return toast.error(error.message);setForm({reason:'',ward:'',bed_id:''});toast.success(`Admission ${data?.admission_id??''} created`);onSaved();};return <div className="space-y-5"><Section title="Admission history">{rows.length?<div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Admitted</th><th className="p-2">Reason</th><th className="p-2">Ward</th><th className="p-2">Status</th></tr></thead><tbody>{rows.map((r:any)=><tr key={r.id} className="border-b"><td className="p-2">{formatDate(r.admitted_at)}</td><td className="p-2">{r.reason||'—'}</td><td className="p-2">{r.ward||'—'}</td><td className="p-2 capitalize">{r.status||'—'}</td></tr>)}</tbody></table></div>:<EmptyState label="admissions"/>}</Section>{canWrite&&<Section title="Create admission"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-2"><input required placeholder="Admission reason" value={form.reason} onChange={e=>setForm({...form,reason:e.target.value})} className="input-medical"/><input placeholder="Ward" value={form.ward} onChange={e=>setForm({...form,ward:e.target.value})} className="input-medical"/><input placeholder="Bed ID (optional)" value={form.bed_id} onChange={e=>setForm({...form,bed_id:e.target.value})} className="input-medical"/><button className="btn-primary">Create admission</button></form></Section>}</div>; }
