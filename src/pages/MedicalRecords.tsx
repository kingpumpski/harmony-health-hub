import { searchPatientDirectory } from '@/lib/patientDirectory';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, Search } from 'lucide-react';
import { toast } from 'sonner';
import { RecordList, StatusBadge } from '@/components/records/RecordList';
import PatientAvatar from '@/components/patients/PatientAvatar';

interface Patient { id: string; patient_code: string; first_name: string; last_name: string; phone: string | null; status: string | null }

function StaffMedicalRecords() {

  const navigate = useNavigate();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    const { data, error } = await searchPatientDirectory('', 300);
    if (error) toast.error(error.message);
    else setPatients((data ?? []) as Patient[]);
    setLoading(false);
  };

  useEffect(() => { void load(); }, []);

  const filtered = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return patients;
    return patients.filter((patient) => {
      const haystack = `${patient.first_name} ${patient.last_name} ${patient.patient_code} ${patient.phone ?? ''}`.toLowerCase();
      return haystack.includes(normalized);
    });
  }, [patients, query]);

  const columns = [
    {
      key: 'patient',
      header: 'Patient',
      render: (patient: Patient) => (
        <div className="flex items-center gap-3">
          <PatientAvatar name={`${patient.first_name} ${patient.last_name}`} size="sm" />
          <div className="min-w-0">
            <p className="font-medium truncate">{patient.first_name} {patient.last_name}</p>
            <p className="text-xs text-muted-foreground">{patient.patient_code}</p>
          </div>
        </div>
      ),
    },
    { key: 'phone', header: 'Phone', hideBelow: 'md' as const, render: (patient: Patient) => patient.phone || 'Not recorded' },
    { key: 'status', header: 'Status', render: (patient: Patient) => <StatusBadge status={patient.status || 'active'} /> },
  ];

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
          <FileText className="w-6 h-6 text-primary" />
          Medical Records
        </h1>
        <p className="text-muted-foreground">Open a patient chart and review the complete clinical record.</p>
      </div>
      <RecordList
        title="Patient medical records"
        description={`${filtered.length} patient record(s) available`}
        data={filtered}
        columns={columns}
        isLoading={loading}
        error={null}
        rowKey={(patient) => patient.id}
        onRowClick={(patient) => navigate(`/patients/${patient.id}`)}
        onRefresh={() => void load()}
        searchSlot={<div className="flex items-center gap-2"><Search className="h-4 w-4 text-muted-foreground" /><input value={query} onChange={(e) => setQuery(e.target.value)} className="input-medical w-full" placeholder="Search by patient name, code or phone…" aria-label="Search medical records" /></div>}
        emptyState={{
          title: query.trim() ? 'No matching patient records' : 'No patient records',
          description: query.trim() ? 'Try another patient name, code or phone number.' : 'No patient records are currently available to this workspace.',
        }}
      />
    </div>
  );
}
function PatientMedicalRecords() {
  const [snapshot, setSnapshot] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    const { data: identity, error: identityError } = await supabase.rpc('get_patient_portal_identity', {});
    const p = Array.isArray(identity) ? identity[0] : identity;
    if (identityError || !p) {
      setError(identityError?.message ?? 'Your patient profile could not be identified.');
      setLoading(false);
      return;
    }
    const { data, error: snapshotError } = await supabase.rpc('get_patient_hub_clinical_snapshot', { _patient_id: p.id });
    if (snapshotError) setError(snapshotError.message);
    else setSnapshot(data ?? null);
    setLoading(false);
  };

  useEffect(() => { void load(); }, []);

  const rows = (value: any) => Array.isArray(value) ? value : [];
  const section = (title: string, items: any[], render: (item: any) => React.ReactNode) => (
    <section className="card-medical p-5">
      <div className="flex items-center justify-between gap-3 mb-3">
        <h2 className="font-semibold">{title}</h2>
        <span className="text-xs rounded-full border px-2.5 py-1">{items.length}</span>
      </div>
      {items.length ? <div className="space-y-2">{items.map((item: any, index: number) => <article key={item.id ?? item.result_id ?? item.lab_order_id ?? index} className="rounded-xl border border-border p-3 text-sm">{render(item)}</article>)}</div> : <p className="text-sm text-muted-foreground">No records available.</p>}
    </section>
  );

  if (loading) return <div className="card-medical p-5 text-sm text-muted-foreground">Loading medical records…</div>;
  if (error) return <div className="card-medical p-5"><p className="text-sm text-critical">{error}</p><button className="btn-secondary mt-3" onClick={() => void load()}>Retry</button></div>;

  const encounters = rows(snapshot?.encounters);
  const diagnoses = rows(snapshot?.diagnoses);
  const labs = rows(snapshot?.labs);
  const imaging = rows(snapshot?.imaging);
  const prescriptions = rows(snapshot?.prescriptions);
  const documents = rows(snapshot?.documents);
  const admissions = rows(snapshot?.admissions);
  const vitals = rows(snapshot?.vitals);

  return <div className="space-y-6 animate-fade-in">
    <div>
      <h1 className="text-2xl font-heading font-bold">Medical Records</h1>
      <p className="text-muted-foreground">Your patient-facing longitudinal medical record, including confirmed diagnoses, documented treatment/care plans, results, medicines, admissions and follow-up information.</p>
    </div>
    <div className="card-medical p-5">
      <p className="text-xs uppercase text-muted-foreground">Patient</p>
      <h2 className="text-xl font-semibold">{snapshot?.patient?.first_name} {snapshot?.patient?.last_name}</h2>
      <p className="text-sm text-muted-foreground">{snapshot?.patient?.patient_code}</p>
    </div>
    <div className="grid gap-6">
      {section('Clinical encounters & clerking', encounters, (x) => <><div className="flex justify-between gap-3"><b>{x.encounter_type || 'Clinical encounter'}</b><span className="text-xs text-muted-foreground">{x.created_at ? new Date(x.created_at).toLocaleString() : ''}</span></div><p className="mt-2 whitespace-pre-wrap">{x.clerking_notes || x.symptoms || 'No narrative note recorded.'}</p>{x.principal_diagnosis && <p className="mt-2"><b>Diagnosis:</b> {x.principal_diagnosis}</p>}{x.treatment_plan && <p className="mt-1"><b>Plan:</b> {x.treatment_plan}</p>}</>)}
      {section('Diagnoses', diagnoses, (x) => <><b>{x.diagnosis}</b>{x.icd_code && <span className="ml-2 text-xs text-muted-foreground">{x.icd_code}</span>}<p className="text-xs text-muted-foreground mt-1">{x.is_principal ? 'Principal diagnosis' : 'Diagnosis'}{x.created_at ? ' · '+new Date(x.created_at).toLocaleString() : ''}</p></>)}
      {section('Laboratory results', labs, (x) => <><b>{x.test_name || 'Laboratory result'}</b><p className="mt-1 whitespace-pre-wrap">{x.result || x.result_data?.value || x.interpretation || 'Result available'}</p>{x.numeric_value != null && <p className="text-xs text-muted-foreground mt-1">{x.numeric_value} {x.unit || ''}{x.abnormal_flag ? ' · '+x.abnormal_flag : ''}</p>}{x.approved_at && <p className="text-xs text-muted-foreground mt-1">Approved {new Date(x.approved_at).toLocaleString()}</p>}</>)}
      {section('Radiology reports', imaging, (x) => <><b>{x.study_name || x.modality || 'Imaging report'}</b><p className="mt-1 whitespace-pre-wrap">{x.impression || x.report || 'Report available'}</p>{x.completed_at && <p className="text-xs text-muted-foreground mt-1">Completed {new Date(x.completed_at).toLocaleString()}</p>}</>)}
      {section('Prescriptions & medicines', prescriptions, (x) => <><b>{x.medication || x.medication_name}</b><p className="text-sm mt-1">{[x.dosage,x.frequency,x.route,x.duration].filter(Boolean).join(' · ') || 'Instructions recorded in clinical record'}</p><p className="text-xs text-muted-foreground mt-1">{x.status || 'recorded'}{x.created_at ? ' · '+new Date(x.created_at).toLocaleString() : ''}</p></>)}
      {section('Vital signs', vitals, (x) => <><b>{x.recorded_at ? new Date(x.recorded_at).toLocaleString() : 'Recorded vitals'}</b><p className="mt-1">BP {x.systolic ?? '—'}/{x.diastolic ?? '—'} · Pulse {x.pulse_rate ?? '—'} · Temp {x.temperature ?? '—'} · SpO₂ {x.oxygen_saturation ?? '—'}%</p><p className="text-xs text-muted-foreground mt-1">Weight {x.weight_kg ?? '—'} kg · Height {x.height_cm ?? '—'} cm · BMI {x.bmi ?? '—'}</p></>)}
      {section('Admissions & discharge history', admissions, (x) => <><b>{x.ward || 'Inpatient admission'}</b><p className="mt-1">{x.status} · Admitted {x.admitted_at ? new Date(x.admitted_at).toLocaleString() : '—'}</p>{x.discharged_at && <p className="text-xs text-muted-foreground mt-1">Discharged {new Date(x.discharged_at).toLocaleString()}</p>}{x.discharge_summary && <p className="mt-2 whitespace-pre-wrap">{x.discharge_summary}</p>}</>)}
      {section('Documents', documents, (x) => <><b>{x.file_name || x.document_type || 'Patient document'}</b>{x.notes && <p className="mt-1">{x.notes}</p>}<p className="text-xs text-muted-foreground mt-1">{x.created_at ? new Date(x.created_at).toLocaleString() : ''}</p>{x.file_url && <a href={x.file_url} target="_blank" rel="noreferrer" className="text-xs text-primary mt-2 inline-flex">Open document</a>}</>)}
    </div>
  </div>;
}
export default function MedicalRecords() { const { user } = useAuth(); return user?.roles?.includes('patient') ? <PatientMedicalRecords /> : <StaffMedicalRecords />; }
