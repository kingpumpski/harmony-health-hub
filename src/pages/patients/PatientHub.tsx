import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { toast } from 'sonner';
import {
  ArrowLeft, CalendarDays, Activity, Stethoscope, FlaskConical, Pill,
  CreditCard, FileText, BedDouble, Save, Upload, RefreshCw, UserRound,
} from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { getPatientById, searchPatients, updatePatient } from '@/lib/healthApi';
import { useAuth } from '@/contexts/AuthContext';

type TabKey = 'profile' | 'appointments' | 'vitals' | 'encounters' | 'labs' | 'prescriptions' | 'billing' | 'documents' | 'admission';

const tabs: { key: TabKey; label: string; icon: React.ElementType }[] = [
  { key: 'profile', label: 'Profile', icon: UserRound },
  { key: 'appointments', label: 'Appointments', icon: CalendarDays },
  { key: 'vitals', label: 'Vitals / Triage', icon: Activity },
  { key: 'encounters', label: 'Encounters', icon: Stethoscope },
  { key: 'labs', label: 'Lab Orders', icon: FlaskConical },
  { key: 'prescriptions', label: 'Prescriptions', icon: Pill },
  { key: 'billing', label: 'Billing', icon: CreditCard },
  { key: 'documents', label: 'Documents', icon: FileText },
  { key: 'admission', label: 'Admission', icon: BedDouble },
];

const editRoles = new Set(['admin', 'practitioner', 'nurse', 'midwife', 'front_desk']);
const clinicalRoles = new Set(['admin', 'practitioner', 'nurse', 'midwife']);
const billingRoles = new Set(['admin', 'accountant', 'front_desk']);

function formatDate(value?: string | null) {
  if (!value) return '—';
  return new Date(value).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
}

function Section({ title, children, action }: { title: string; children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <section className="card-medical p-5 space-y-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <h2 className="text-lg font-semibold">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}

function EmptyState({ label }: { label: string }) {
  return <p className="rounded-2xl border border-dashed border-border p-6 text-sm text-muted-foreground">No {label} recorded yet.</p>;
}

export default function PatientHub() {
  const { patientId } = useParams<{ patientId: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [patient, setPatient] = useState<any>(null);
  const [activeTab, setActiveTab] = useState<TabKey>('profile');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const [rows, setRows] = useState<Record<string, any[]>>({});

  const canEdit = Boolean(user && editRoles.has(user.role));
  const canClinicalWrite = Boolean(user && clinicalRoles.has(user.role));
  const canBill = Boolean(user && billingRoles.has(user.role));

  const loadPatient = useCallback(async () => {
    if (!patientId) return;
    setLoading(true);
    try {
      const data = await getPatientById(patientId);
      if (!data) {
        const matches = await searchPatients(patientId);
        const match = matches[0];
        if (match?.id) {
          navigate(`/patients/${match.id}`, { replace: true });
          return;
        }
      }
      setPatient(data);
    } catch (error: any) {
      toast.error(error.message ?? 'Unable to load patient');
    } finally {
      setLoading(false);
    }
  }, [navigate, patientId]);

  const loadHistory = useCallback(async () => {
    if (!patientId) return;
    const db = supabase as any;
    const [appointments, vitals, encounters, labs, prescriptions, invoices, documents, admissions] = await Promise.all([
      db.from('appointments').select('*').eq('patient_id', patientId).order('scheduled_at', { ascending: false }).limit(100),
      db.from('vital_signs').select('*').eq('patient_id', patientId).order('recorded_at', { ascending: false }).limit(100),
      db.from('encounters').select('*').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(100),
      db.from('lab_orders').select('*').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(100),
      db.from('prescriptions').select('*').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(100),
      db.from('invoices').select('*').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(100),
      db.from('patient_documents').select('*').eq('patient_id', patientId).order('created_at', { ascending: false }).limit(100),
      db.from('admissions').select('*').eq('patient_id', patientId).order('admitted_at', { ascending: false }).limit(50),
    ]);
    const errors = [appointments, vitals, encounters, labs, prescriptions, invoices, documents, admissions].map((r) => r.error).filter(Boolean);
    if (errors.length) throw errors[0];
    setRows({
      appointments: appointments.data ?? [],
      vitals: vitals.data ?? [],
      encounters: encounters.data ?? [],
      labs: labs.data ?? [],
      prescriptions: prescriptions.data ?? [],
      invoices: invoices.data ?? [],
      documents: documents.data ?? [],
      admissions: admissions.data ?? [],
    });
  }, [patientId]);

  useEffect(() => { void loadPatient(); }, [loadPatient]);
  useEffect(() => {
    if (patient) void loadHistory().catch((error: any) => toast.error(error.message ?? 'Unable to load patient history'));
  }, [loadHistory, patient, refreshKey]);

  const refresh = () => setRefreshKey((value) => value + 1);

  if (loading) return <div className="p-8 text-sm text-muted-foreground">Loading patient record…</div>;
  if (!patient) return <div className="p-8 space-y-4"><p className="font-medium">Patient record not found.</p><Link to="/patients" className="btn-secondary inline-flex">Back to search</Link></div>;

  return (
    <div className="space-y-5 animate-fade-in">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate('/patients')} className="p-2 rounded-lg hover:bg-muted" aria-label="Back to patient search"><ArrowLeft className="w-5 h-5" /></button>
          <div>
            <h1 className="text-2xl font-heading font-bold">{patient.first_name} {patient.last_name}</h1>
            <p className="text-sm text-muted-foreground">Patient code: {patient.patient_code} · {patient.status}</p>
          </div>
        </div>
        <button onClick={refresh} className="btn-secondary inline-flex items-center justify-center gap-2"><RefreshCw className="w-4 h-4" /> Refresh record</button>
      </div>

      <div className="overflow-x-auto rounded-2xl border border-border bg-card">
        <div className="flex min-w-max gap-1 p-2">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            return <button key={tab.key} onClick={() => setActiveTab(tab.key)} className={`inline-flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-medium ${activeTab === tab.key ? 'bg-primary text-primary-foreground' : 'hover:bg-muted text-muted-foreground'}`}><Icon className="w-4 h-4" />{tab.label}</button>;
          })}
        </div>
      </div>

      {activeTab === 'profile' && <ProfileTab patient={patient} canEdit={canEdit} onSaved={(next) => setPatient(next)} />}
      {activeTab === 'appointments' && <AppointmentsTab patientId={patient.id} rows={rows.appointments ?? []} canWrite={canClinicalWrite} onSaved={refresh} />}
      {activeTab === 'vitals' && <VitalsTab patientId={patient.id} rows={rows.vitals ?? []} canWrite={canClinicalWrite} onSaved={refresh} />}
      {activeTab === 'encounters' && <EncountersTab patientId={patient.id} rows={rows.encounters ?? []} canWrite={canClinicalWrite} onSaved={refresh} />}
      {activeTab === 'labs' && <LabsTab patientId={patient.id} rows={rows.labs ?? []} canWrite={canClinicalWrite} onSaved={refresh} />}
      {activeTab === 'prescriptions' && <PrescriptionsTab patientId={patient.id} rows={rows.prescriptions ?? []} canWrite={canClinicalWrite} onSaved={refresh} />}
      {activeTab === 'billing' && <BillingTab patientId={patient.id} rows={rows.invoices ?? []} canWrite={canBill} onSaved={refresh} />}
      {activeTab === 'documents' && <DocumentsTab patientId={patient.id} rows={rows.documents ?? []} canWrite={canEdit} onSaved={refresh} />}
      {activeTab === 'admission' && <AdmissionTab patientId={patient.id} rows={rows.admissions ?? []} canWrite={canClinicalWrite} onSaved={refresh} />}
    </div>
  );
}

function ProfileTab({ patient, canEdit, onSaved }: { patient: any; canEdit: boolean; onSaved: (patient: any) => void }) {
  const [form, setForm] = useState({
    first_name: patient.first_name ?? '', last_name: patient.last_name ?? '', date_of_birth: patient.date_of_birth ?? '',
    gender: patient.gender ?? '', phone: patient.phone ?? '', email: patient.email ?? '', address: patient.address ?? '', city: patient.city ?? '',
    ghana_card_number: patient.ghana_card_number ?? '', blood_group: patient.blood_group ?? '', genotype: patient.genotype ?? '',
    allergies: patient.allergies ?? '', chronic_conditions: patient.chronic_conditions ?? '', insurance_provider: patient.insurance_provider ?? '',
    insurance_number: patient.insurance_number ?? '', insurance_group_number: patient.insurance_group_number ?? '', insurance_expiry: patient.insurance_expiry ?? '',
    emergency_contact_name: patient.emergency_contact_name ?? '', emergency_contact_phone: patient.emergency_contact_phone ?? '', emergency_contact_relation: patient.emergency_contact_relation ?? '',
  });
  const [saving, setSaving] = useState(false);
  const update = (key: string, value: string) => setForm((current) => ({ ...current, [key]: value }));

  const save = async (event: FormEvent) => {
    event.preventDefault();
    setSaving(true);
    try {
      await updatePatient(patient.id, form as any);
      const next = { ...patient, ...form };
      onSaved(next);
      toast.success('Patient record updated. The change was added to the audit trail.');
    } catch (error: any) {
      toast.error(error.message ?? 'Could not update patient record');
    } finally { setSaving(false); }
  };

  const fields = [
    ['first_name','First name'],['last_name','Last name'],['date_of_birth','Date of birth'],['phone','Phone'],['email','Email'],['address','Address'],['city','City'],
    ['ghana_card_number','Ghana Card / national identifier'],['blood_group','Blood group'],['genotype','Genotype'],['insurance_provider','Insurance provider'],['insurance_number','Insurance policy number'],
    ['insurance_group_number','Insurance group number'],['insurance_expiry','Insurance expiry'],['emergency_contact_name','Emergency contact'],['emergency_contact_phone','Emergency phone'],['emergency_contact_relation','Emergency relationship'],
  ] as const;

  return <Section title="Patient demographic and administrative record">
    <form onSubmit={save} className="space-y-5">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {fields.map(([key, label]) => <label key={key} className="space-y-1 text-sm"><span className="font-medium">{label}</span><input type={key.includes('date') || key === 'insurance_expiry' ? 'date' : key === 'email' ? 'email' : key.includes('phone') ? 'tel' : 'text'} value={form[key] ?? ''} onChange={(e) => update(key, e.target.value)} disabled={!canEdit} className="input-medical w-full" /></label>)}
        <label className="space-y-1 text-sm"><span className="font-medium">Gender</span><select value={form.gender} onChange={(e) => update('gender', e.target.value)} disabled={!canEdit} className="input-medical w-full"><option value="">Not recorded</option><option value="male">Male</option><option value="female">Female</option><option value="other">Other</option></select></label>
        <label className="space-y-1 text-sm sm:col-span-2"><span className="font-medium">Allergies</span><textarea value={form.allergies} onChange={(e) => update('allergies', e.target.value)} disabled={!canEdit} className="input-medical min-h-20 w-full" /></label>
        <label className="space-y-1 text-sm sm:col-span-2"><span className="font-medium">Chronic conditions</span><textarea value={form.chronic_conditions} onChange={(e) => update('chronic_conditions', e.target.value)} disabled={!canEdit} className="input-medical min-h-20 w-full" /></label>
      </div>
      {canEdit ? <button disabled={saving} className="btn-primary inline-flex items-center gap-2"><Save className="w-4 h-4" />{saving ? 'Saving…' : 'Save patient changes'}</button> : <p className="text-sm text-muted-foreground">Your role has read-only access to patient demographics.</p>}
    </form>
  </Section>;
}

function AppointmentsTab({ patientId, rows, canWrite, onSaved }: any) {
  const [form, setForm] = useState({ scheduled_at: '', department: '', reason: '' });
  const submit = async (e: FormEvent) => { e.preventDefault(); const { error } = await (supabase as any).from('appointments').insert({ patient_id: patientId, scheduled_at: form.scheduled_at, department: form.department || null, reason: form.reason || null }); if (error) return toast.error(error.message); setForm({ scheduled_at: '', department: '', reason: '' }); toast.success('Appointment added'); onSaved(); };
  return <div className="space-y-5"><Section title="Appointment history" action={canWrite ? <span className="text-xs text-muted-foreground">Clinical staff can add appointments</span> : null}>{rows.length ? <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Scheduled</th><th className="p-2">Department</th><th className="p-2">Reason</th><th className="p-2">Status</th></tr></thead><tbody>{rows.map((r: any) => <tr key={r.id} className="border-b"><td className="p-2">{formatDate(r.scheduled_at)}</td><td className="p-2">{r.department || '—'}</td><td className="p-2">{r.reason || '—'}</td><td className="p-2 capitalize">{r.status}</td></tr>)}</tbody></table></div> : <EmptyState label="appointments" />}</Section>{canWrite && <Section title="Add appointment"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-3"><input required type="datetime-local" value={form.scheduled_at} onChange={(e) => setForm({ ...form, scheduled_at: e.target.value })} className="input-medical" /><input placeholder="Department" value={form.department} onChange={(e) => setForm({ ...form, department: e.target.value })} className="input-medical" /><input placeholder="Reason" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} className="input-medical" /><button className="btn-primary sm:col-span-3 inline-flex items-center justify-center gap-2"><Save className="w-4 h-4" />Add appointment</button></form></Section>}</div>;
}

function VitalsTab({ patientId, rows, canWrite, onSaved }: any) {
  const [form, setForm] = useState({ systolic: '', diastolic: '', pulse_rate: '', temperature: '', respiratory_rate: '', oxygen_saturation: '', weight_kg: '', height_cm: '', notes: '' });
  const bmi = useMemo(() => { const w = Number(form.weight_kg), h = Number(form.height_cm) / 100; return w > 0 && h > 0 ? (w / (h * h)).toFixed(1) : ''; }, [form.weight_kg, form.height_cm]);
  const submit = async (e: FormEvent) => { e.preventDefault(); const sys = Number(form.systolic); const spo2 = Number(form.oxygen_saturation); const pulse = Number(form.pulse_rate); const temp = Number(form.temperature); const priority = temp >= 39 || spo2 <= 92 || pulse >= 120 || sys >= 180 ? 'critical' : temp >= 38 || spo2 <= 94 || pulse >= 100 || sys >= 160 ? 'urgent' : 'moderate'; const { error } = await (supabase as any).from('vital_signs').insert({ patient_id: patientId, recorded_by: (await supabase.auth.getUser()).data.user?.id, systolic: sys || null, diastolic: Number(form.diastolic) || null, pulse_rate: pulse || null, temperature: temp || null, respiratory_rate: Number(form.respiratory_rate) || null, oxygen_saturation: spo2 || null, weight_kg: Number(form.weight_kg) || null, height_cm: Number(form.height_cm) || null, bmi: bmi ? Number(bmi) : null, priority, notes: form.notes || null }); if (error) return toast.error(error.message); setForm({ systolic: '', diastolic: '', pulse_rate: '', temperature: '', respiratory_rate: '', oxygen_saturation: '', weight_kg: '', height_cm: '', notes: '' }); toast.success(`Vitals recorded · ${priority} priority`); onSaved(); };
  return <div className="space-y-5"><Section title="Vitals / triage history">{rows.length ? <div className="grid gap-3">{rows.map((r: any) => <div key={r.id} className="rounded-2xl border border-border p-4"><div className="flex flex-wrap justify-between gap-2"><b>{formatDate(r.recorded_at)}</b><span className="capitalize rounded-full bg-primary/10 px-3 py-1 text-xs font-medium">{r.priority || 'not scored'}</span></div><p className="mt-2 text-sm">BP {r.systolic ?? '—'}/{r.diastolic ?? '—'} · Pulse {r.pulse_rate ?? '—'} · Temp {r.temperature ?? '—'}° · SpO₂ {r.oxygen_saturation ?? '—'}% · BMI {r.bmi ?? '—'}</p>{r.notes && <p className="mt-1 text-sm text-muted-foreground">{r.notes}</p>}</div>)}</div> : <EmptyState label="vital observations" />}</Section>{canWrite && <Section title="Start triage / record vitals"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">{[['systolic','Systolic BP'],['diastolic','Diastolic BP'],['pulse_rate','Pulse / min'],['temperature','Temperature °C'],['respiratory_rate','Respiratory / min'],['oxygen_saturation','SpO₂ %'],['weight_kg','Weight kg'],['height_cm','Height cm']].map(([key,label]) => <label key={key} className="text-sm space-y-1"><span className="font-medium">{label}</span><input required={['systolic','diastolic','pulse_rate','temperature','oxygen_saturation'].includes(key)} type="number" step="any" value={(form as any)[key]} onChange={(e) => setForm({ ...form, [key]: e.target.value })} className="input-medical w-full" /></label>)}<div className="rounded-xl bg-muted p-3 text-sm">Auto BMI: <b>{bmi || '—'}</b></div><label className="sm:col-span-2 lg:col-span-3 text-sm space-y-1"><span className="font-medium">Clinical notes</span><input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} className="input-medical w-full" /></label><button className="btn-primary lg:col-span-4 inline-flex justify-center gap-2"><Activity className="w-4 h-4" />Save triage</button></form></Section>}</div>;
}

function EncountersTab({ patientId, rows, canWrite, onSaved }: any) {
  const [form, setForm] = useState({ symptoms: '', clerking_notes: '', principal_diagnosis: '', treatment_plan: '' });
  const submit = async (e: FormEvent) => { e.preventDefault(); const { error } = await (supabase as any).from('encounters').insert({ patient_id: patientId, practitioner_id: (await supabase.auth.getUser()).data.user?.id, symptoms: form.symptoms || null, clerking_notes: form.clerking_notes || null, principal_diagnosis: form.principal_diagnosis || null, treatment_plan: form.treatment_plan || null }); if (error) return toast.error(error.message); setForm({ symptoms: '', clerking_notes: '', principal_diagnosis: '', treatment_plan: '' }); toast.success('Encounter created'); onSaved(); };
  return <div className="space-y-5"><Section title="Encounter history">{rows.length ? <div className="space-y-3">{rows.map((r: any) => <div key={r.id} className="rounded-2xl border p-4"><div className="flex justify-between gap-3"><b>{formatDate(r.created_at)}</b><span className="capitalize text-xs">{r.status}</span></div><p className="mt-2"><b>Diagnosis:</b> {r.principal_diagnosis || 'Not recorded'}</p><p className="text-sm text-muted-foreground mt-1">{r.symptoms || r.clerking_notes || 'No clinical narrative recorded.'}</p></div>)}</div> : <EmptyState label="encounters" />}</Section>{canWrite && <Section title="Add encounter"><form onSubmit={submit} className="space-y-4"><textarea required placeholder="Symptoms / chief complaint" value={form.symptoms} onChange={(e) => setForm({ ...form, symptoms: e.target.value })} className="input-medical min-h-20 w-full" /><textarea placeholder="Clerking notes" value={form.clerking_notes} onChange={(e) => setForm({ ...form, clerking_notes: e.target.value })} className="input-medical min-h-20 w-full" /><input placeholder="Principal diagnosis" value={form.principal_diagnosis} onChange={(e) => setForm({ ...form, principal_diagnosis: e.target.value })} className="input-medical w-full" /><textarea placeholder="Treatment plan" value={form.treatment_plan} onChange={(e) => setForm({ ...form, treatment_plan: e.target.value })} className="input-medical min-h-20 w-full" /><button className="btn-primary inline-flex gap-2"><Save className="w-4 h-4" />Create encounter</button></form></Section>}</div>;
}

function LabsTab({ patientId, rows, canWrite, onSaved }: any) {
  const [form, setForm] = useState({ test_name: '', test_category: '', priority: 'routine', clinical_notes: '' });
  const submit = async (e: FormEvent) => { e.preventDefault(); const { error } = await (supabase as any).from('lab_orders').insert({ patient_id: patientId, ordered_by: (await supabase.auth.getUser()).data.user?.id, ...form }); if (error) return toast.error(error.message); setForm({ test_name: '', test_category: '', priority: 'routine', clinical_notes: '' }); toast.success('Lab order created'); onSaved(); };
  return <div className="space-y-5"><Section title="Laboratory order history">{rows.length ? <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Date</th><th className="p-2">Test</th><th className="p-2">Category</th><th className="p-2">Priority</th><th className="p-2">Status</th></tr></thead><tbody>{rows.map((r: any) => <tr key={r.id} className="border-b"><td className="p-2">{formatDate(r.created_at)}</td><td className="p-2 font-medium">{r.test_name}</td><td className="p-2">{r.test_category || '—'}</td><td className="p-2 capitalize">{r.priority}</td><td className="p-2 capitalize">{r.status}</td></tr>)}</tbody></table></div> : <EmptyState label="lab orders" />}</Section>{canWrite && <Section title="Order a laboratory test"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-2"><input required placeholder="Test name" value={form.test_name} onChange={(e) => setForm({ ...form, test_name: e.target.value })} className="input-medical" /><input placeholder="Category" value={form.test_category} onChange={(e) => setForm({ ...form, test_category: e.target.value })} className="input-medical" /><select value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })} className="input-medical"><option value="routine">Routine</option><option value="urgent">Urgent</option><option value="stat">STAT</option></select><input placeholder="Clinical notes" value={form.clinical_notes} onChange={(e) => setForm({ ...form, clinical_notes: e.target.value })} className="input-medical" /><button className="btn-primary sm:col-span-2 inline-flex gap-2"><FlaskConical className="w-4 h-4" />Create lab order</button></form></Section>}</div>;
}

function PrescriptionsTab({ patientId, rows, canWrite, onSaved }: any) {
  const [form, setForm] = useState({ medication: '', dosage: '', frequency: '', duration: '', instructions: '' });
  const submit = async (e: FormEvent) => { e.preventDefault(); const { error } = await (supabase as any).from('prescriptions').insert({ patient_id: patientId, prescribed_by: (await supabase.auth.getUser()).data.user?.id, ...form }); if (error) return toast.error(error.message); setForm({ medication: '', dosage: '', frequency: '', duration: '', instructions: '' }); toast.success('Prescription recorded'); onSaved(); };
  return <div className="space-y-5"><Section title="Prescription history">{rows.length ? <div className="grid gap-3">{rows.map((r: any) => <div key={r.id} className="rounded-2xl border p-4"><div className="flex justify-between gap-3"><b>{r.medication}</b><span className="capitalize text-xs">{r.status}</span></div><p className="text-sm mt-1">{r.dosage || '—'} · {r.frequency || '—'} · {r.duration || '—'}</p>{r.instructions && <p className="text-sm text-muted-foreground mt-1">{r.instructions}</p>}</div>)}</div> : <EmptyState label="prescriptions" />}</Section>{canWrite && <Section title="Add prescription"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-2"><input required placeholder="Medication" value={form.medication} onChange={(e) => setForm({ ...form, medication: e.target.value })} className="input-medical" /><input placeholder="Dose" value={form.dosage} onChange={(e) => setForm({ ...form, dosage: e.target.value })} className="input-medical" /><input placeholder="Frequency" value={form.frequency} onChange={(e) => setForm({ ...form, frequency: e.target.value })} className="input-medical" /><input placeholder="Duration" value={form.duration} onChange={(e) => setForm({ ...form, duration: e.target.value })} className="input-medical" /><input placeholder="Instructions" value={form.instructions} onChange={(e) => setForm({ ...form, instructions: e.target.value })} className="input-medical sm:col-span-2" /><button className="btn-primary sm:col-span-2 inline-flex gap-2"><Pill className="w-4 h-4" />Record prescription</button></form></Section>}</div>;
}

function BillingTab({ patientId, rows, canWrite, onSaved }: any) {
  const [form, setForm] = useState({ total_amount: '', notes: '' });
  const submit = async (e: FormEvent) => { e.preventDefault(); const { error } = await (supabase as any).from('invoices').insert({ patient_id: patientId, invoice_number: `INV-${Date.now()}`, total_amount: Number(form.total_amount), created_by: (await supabase.auth.getUser()).data.user?.id, notes: form.notes || null }); if (error) return toast.error(error.message); setForm({ total_amount: '', notes: '' }); toast.success('Invoice created'); onSaved(); };
  return <div className="space-y-5"><Section title="Billing history">{rows.length ? <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Invoice</th><th className="p-2">Date</th><th className="p-2">Total</th><th className="p-2">Paid</th><th className="p-2">Status</th></tr></thead><tbody>{rows.map((r: any) => <tr key={r.id} className="border-b"><td className="p-2 font-medium">{r.invoice_number}</td><td className="p-2">{formatDate(r.created_at)}</td><td className="p-2">{r.total_amount}</td><td className="p-2">{r.paid_amount}</td><td className="p-2 capitalize">{r.status}</td></tr>)}</tbody></table></div> : <EmptyState label="billing records" />}</Section>{canWrite && <Section title="Create invoice"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-2"><input required min="0" type="number" step="0.01" placeholder="Total amount" value={form.total_amount} onChange={(e) => setForm({ ...form, total_amount: e.target.value })} className="input-medical" /><input placeholder="Notes" value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} className="input-medical" /><button className="btn-primary sm:col-span-2 inline-flex gap-2"><CreditCard className="w-4 h-4" />Create invoice</button></form></Section>}</div>;
}

function DocumentsTab({ patientId, rows, canWrite, onSaved }: any) {
  const [file, setFile] = useState<File | null>(null);
  const [type, setType] = useState('other');
  const [notes, setNotes] = useState('');
  const submit = async (e: FormEvent) => { e.preventDefault(); if (!file) return; const userId = (await supabase.auth.getUser()).data.user?.id; if (!userId) return toast.error('You must be signed in.'); const path = `${patientId}/${crypto.randomUUID()}-${file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`; const { error: uploadError } = await supabase.storage.from('patient-documents').upload(path, file, { contentType: file.type, upsert: false }); if (uploadError) return toast.error(uploadError.message); const { error } = await (supabase as any).from('patient_documents').insert({ patient_id: patientId, document_type: type, file_name: file.name, storage_path: path, mime_type: file.type, file_size: file.size, notes: notes || null, uploaded_by: userId }); if (error) { await supabase.storage.from('patient-documents').remove([path]); return toast.error(error.message); } setFile(null); setNotes(''); toast.success('Patient document uploaded'); onSaved(); };
  const openDocument = async (path: string) => { const { data, error } = await supabase.storage.from('patient-documents').createSignedUrl(path, 300); if (error) return toast.error(error.message); window.open(data.signedUrl, '_blank', 'noopener,noreferrer'); };
  return <div className="space-y-5"><Section title="Patient documents">{rows.length ? <div className="space-y-3">{rows.map((r: any) => <div key={r.id} className="flex flex-col gap-3 rounded-2xl border p-4 sm:flex-row sm:items-center sm:justify-between"><div><p className="font-medium">{r.file_name}</p><p className="text-xs text-muted-foreground capitalize">{r.document_type} · {formatDate(r.created_at)} · {r.file_size ? `${Math.ceil(r.file_size / 1024)} KB` : 'size unknown'}</p>{r.notes && <p className="text-sm text-muted-foreground mt-1">{r.notes}</p>}</div>{r.storage_path && <button onClick={() => openDocument(r.storage_path)} className="btn-secondary">Open securely</button>}</div>)}</div> : <EmptyState label="documents" />}</Section>{canWrite && <Section title="Upload document"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-2"><input required type="file" onChange={(e) => setFile(e.target.files?.[0] ?? null)} className="input-medical" /><select value={type} onChange={(e) => setType(e.target.value)} className="input-medical"><option value="other">Other</option><option value="identity">Identity</option><option value="referral">Referral</option><option value="clinical">Clinical record</option><option value="laboratory">Laboratory</option><option value="imaging">Imaging</option><option value="insurance">Insurance</option></select><input placeholder="Document notes" value={notes} onChange={(e) => setNotes(e.target.value)} className="input-medical sm:col-span-2" /><button className="btn-primary sm:col-span-2 inline-flex gap-2"><Upload className="w-4 h-4" />Upload document</button></form></Section>}</div>;
}

function AdmissionTab({ patientId, rows, canWrite, onSaved }: any) {
  const [form, setForm] = useState({ ward: '', bed: '', diagnosis: '', notes: '' });
  const submit = async (e: FormEvent) => { e.preventDefault(); const { error } = await (supabase as any).from('admissions').insert({ patient_id: patientId, ward: form.ward || null, bed: form.bed || null, diagnosis: form.diagnosis || null, notes: form.notes || null, admitting_practitioner: (await supabase.auth.getUser()).data.user?.id, created_by: (await supabase.auth.getUser()).data.user?.id }); if (error) return toast.error(error.message); setForm({ ward: '', bed: '', diagnosis: '', notes: '' }); toast.success('Admission recorded'); onSaved(); };
  return <div className="space-y-5"><Section title="Admission history">{rows.length ? <div className="grid gap-3">{rows.map((r: any) => <div key={r.id} className="rounded-2xl border p-4"><div className="flex justify-between gap-3"><b>{r.ward || 'Ward not recorded'} {r.bed ? `· Bed ${r.bed}` : ''}</b><span className="capitalize text-xs">{r.status}</span></div><p className="text-sm mt-1">Admitted: {formatDate(r.admitted_at)}{r.discharged_at ? ` · Discharged: ${formatDate(r.discharged_at)}` : ''}</p><p className="text-sm mt-1"><b>Diagnosis:</b> {r.diagnosis || 'Not recorded'}</p></div>)}</div> : <EmptyState label="admissions" />}</Section>{canWrite && <Section title="Admit patient"><form onSubmit={submit} className="grid gap-4 sm:grid-cols-2"><input placeholder="Ward" value={form.ward} onChange={(e) => setForm({ ...form, ward: e.target.value })} className="input-medical" /><input placeholder="Bed" value={form.bed} onChange={(e) => setForm({ ...form, bed: e.target.value })} className="input-medical" /><input placeholder="Admission diagnosis" value={form.diagnosis} onChange={(e) => setForm({ ...form, diagnosis: e.target.value })} className="input-medical sm:col-span-2" /><textarea placeholder="Admission notes" value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} className="input-medical min-h-20 sm:col-span-2" /><button className="btn-primary sm:col-span-2 inline-flex gap-2"><BedDouble className="w-4 h-4" />Admit patient</button></form></Section>}</div>;
}
