import { FormEvent, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, Loader2, UserPlus, MessageSquare, Activity, XCircle } from 'lucide-react';
import { searchPatients } from '@/lib/healthApi';
import { useAuth } from '@/contexts/AuthContext';
import { RecordList, StatusBadge } from '@/components/records/RecordList';
import PatientAvatar from '@/components/patients/PatientAvatar';

interface PatientSearchResult {
  id: string;
  patientId: string;
  firstName: string;
  lastName: string;
  fullName: string;
  phone: string | null;
  ghanaCardNumber: string | null;
  status: string;
  insuranceProvider: string | null;
}

export default function PatientSearch() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const roleSet = new Set(user?.roles ?? (user ? [user.role] : []));
  const canRegister = roleSet.has('admin') || roleSet.has('front_desk');
  const canChat = roleSet.has('admin') || roleSet.has('practitioner') || roleSet.has('nurse') || roleSet.has('specialist_nurse') || roleSet.has('midwife') || roleSet.has('patient');
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<PatientSearchResult[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState('Search by patient name, patient code, phone, email or Ghana Card.');
  const [error, setError] = useState('');
  const [hasSearched, setHasSearched] = useState(false);

  const handleSearch = async (event?: FormEvent) => {
    event?.preventDefault();
    const value = query.trim();
    if (!value) {
      setResults([]);
      setError('');
      setHasSearched(false);
      setMessage('Enter a search term to find a patient.');
      return;
    }
    setIsLoading(true);
    setHasSearched(true);
    setError('');
    try {
      const items = await searchPatients(value);
      setResults(items as PatientSearchResult[]);
      setMessage(items.length ? `${items.length} patient(s) found.` : 'No matching patients found.');
    } catch (searchError) {
      setResults([]);
      setMessage('Search could not be completed.');
      setError(searchError instanceof Error ? searchError.message : 'Unable to search patients right now.');
    } finally {
      setIsLoading(false);
    }
  };

  const columns = [
    {
      key: 'patient',
      header: 'Patient',
      render: (patient: PatientSearchResult) => (
        <div className="flex items-center gap-3">
          <PatientAvatar name={patient.fullName} size="sm" />
          <div className="min-w-0">
            <p className="font-medium truncate">{patient.fullName}</p>
            <p className="text-xs text-muted-foreground">{patient.patientId}</p>
          </div>
        </div>
      ),
    },
    { key: 'phone', header: 'Phone', hideBelow: 'md' as const, render: (patient: PatientSearchResult) => patient.phone || 'Not available' },
    { key: 'ghanaCardNumber', header: 'Ghana Card', hideBelow: 'lg' as const, render: (patient: PatientSearchResult) => patient.ghanaCardNumber || 'Not available' },
    { key: 'insuranceProvider', header: 'Insurance', hideBelow: 'lg' as const, render: (patient: PatientSearchResult) => patient.insuranceProvider || 'Self-pay / not recorded' },
    { key: 'status', header: 'Status', render: (patient: PatientSearchResult) => <StatusBadge status={patient.status || 'active'} /> },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right' as const,
      render: (patient: PatientSearchResult) => (
        <div className="flex justify-end gap-1" onClick={(event) => event.stopPropagation()}>
          <button type="button" className="btn-ghost h-8 w-8 p-0" onClick={() => navigate(`/patients/${patient.id}?vitals=1`)} aria-label={`View vitals for ${patient.fullName}`}>
            <Activity className="h-4 w-4" />
          </button>
          {canChat && <button type="button" className="btn-ghost h-8 w-8 p-0" onClick={() => navigate(`/patients/${patient.id}/chat`)} aria-label={`Open chat for ${patient.fullName}`}>
            <MessageSquare className="h-4 w-4" />
          </button>}
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Patient Search</h1>
          <p className="text-muted-foreground">Open the complete patient hub without leaving the search workflow.</p>
        </div>
      </div>

      <form onSubmit={handleSearch} className="card-medical p-5 sm:p-6 space-y-4">
        <div className="relative">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search by name, patient code, Ghana Card, phone or email" className="input-medical pl-12 w-full" autoComplete="off" enterKeyHint="search" aria-describedby="patient-search-help" />
        </div>
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div className="flex gap-2">
            <button type="submit" disabled={isLoading} className="btn-primary inline-flex items-center justify-center gap-2 disabled:opacity-60">
              {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Search className="w-4 h-4" />}Search Patients
            </button>
            {query && <button type="button" onClick={() => { setQuery(''); setResults([]); setHasSearched(false); setError(''); setMessage('Enter a search term to find a patient.'); }} className="btn-secondary">Clear</button>}
          </div>
          <span className="text-sm text-muted-foreground">{message}</span>
        </div>
        <p id="patient-search-help" className="text-xs text-muted-foreground">Use a patient code, name, Ghana Card, phone number or email. Avoid entering unnecessary clinical information.</p>
        {error && <div role="alert" className="flex items-start gap-2 rounded-xl border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"><XCircle className="mt-0.5 h-4 w-4 shrink-0" />{error}</div>}
      </form>

      <RecordList
        title="Patient directory"
        description={hasSearched ? `${results.length} matching patient record(s)` : 'Search results appear here after you run a patient search.'}
        data={results}
        columns={columns}
        isLoading={isLoading}
        error={error}
        rowKey={(patient) => patient.id}
        onRowClick={(patient) => navigate(`/patients/${patient.id}`)}
        onAddNew={canRegister ? () => navigate('/registration') : undefined}
        onRefresh={() => void handleSearch()}
        addNewLabel="Register Patient"
        emptyState={{
          title: hasSearched ? 'No matching patients' : 'No patient search results',
          description: hasSearched ? 'Check the identifier or search using the patient’s full name.' : 'Enter a patient identifier above to begin.',
          cta: canRegister && hasSearched ? <button type="button" className="btn-secondary" onClick={() => navigate('/registration')}><UserPlus className="mr-2 h-4 w-4" />Register a new patient</button> : undefined,
        }}
      />
    </div>
  );
}
