import { searchPatientDirectory } from '@/lib/patientDirectory';
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
      <div className="card-medical p-4 flex items-center gap-3">
        <Search className="w-5 h-5 text-muted-foreground" />
        <input value={query} onChange={(e) => setQuery(e.target.value)} className="input-medical flex-1" placeholder="Search by patient name, code or phone…" aria-label="Filter medical records" />
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
  useEffect(() => {
    (async () => {
      const { data: identity } = await supabase.rpc('get_patient_portal_identity');
      const p = Array.isArray(identity) ? identity[0] : identity;
      if (!p) { setLoading(false); return; }
      const { data } = await supabase.rpc('get_patient_hub_clinical_snapshot', { _patient_id: p.id });
      setSnapshot(data ?? null); setLoading(false);
    })();
  }, []);
  const section = (title: string, value: any) => <div className="card-medical p-5"><h2 className="font-semibold mb-3">{title}</h2>{Array.isArray(value) && value.length ? <div className="space-y-2">{value.map((x:any,i:number)=><pre key={x.id||i} className="text-xs whitespace-pre-wrap rounded-lg bg-muted/40 p-3">{JSON.stringify(x,null,2)}</pre>)}</div> : <p className="text-sm text-muted-foreground">No records available.</p>}</div>;
  return <div className="space-y-6 animate-fade-in"><div><h1 className="text-2xl font-heading font-bold">Medical Records</h1><p className="text-muted-foreground">Read-only access to your available clinical records.</p></div>{loading ? <p className="text-sm text-muted-foreground">Loading medical records…</p> : snapshot ? <div className="grid gap-6">{section('Laboratory results',snapshot.lab_results||snapshot.labs)}{section('Radiology reports',snapshot.radiology_reports||snapshot.imaging)}{section('Clinical notes',snapshot.encounters||snapshot.clinical_notes)}</div> : <div className="card-medical p-5"><p className="text-sm text-muted-foreground">Your medical records are temporarily unavailable.</p></div>}</div>;
}

export default function MedicalRecords() { const { user } = useAuth(); return user?.roles?.includes('patient') ? <PatientMedicalRecords /> : <StaffMedicalRecords />; }
