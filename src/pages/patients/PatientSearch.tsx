import { FormEvent, useState } from 'react';
import { Link } from 'react-router-dom';
import { Search, Loader2, UserPlus, MessageSquare, ArrowRight } from 'lucide-react';
import { searchPatients } from '@/lib/healthApi';

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
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<PatientSearchResult[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState('Search by patient name, patient code, phone, email or Ghana Card.');

  const handleSearch = async (event: FormEvent) => {
    event.preventDefault();
    const value = query.trim();
    if (!value) {
      setResults([]);
      setMessage('Enter a search term to find a patient.');
      return;
    }

    setIsLoading(true);
    try {
      const items = await searchPatients(value);
      setResults(items as PatientSearchResult[]);
      setMessage(items.length ? `${items.length} patient(s) found.` : 'No matching patients found.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Patient Search</h1>
          <p className="text-muted-foreground">Open the complete patient hub without leaving the search workflow.</p>
        </div>
        <Link to="/registration" className="btn-primary inline-flex items-center justify-center gap-2">
          <UserPlus className="w-4 h-4" />
          Register Patient
        </Link>
      </div>

      <form onSubmit={handleSearch} className="card-medical p-6">
        <div className="relative">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search by name, patient code, Ghana Card, phone or email"
            className="input-medical pl-12 w-full"
            aria-label="Search patients"
          />
        </div>
        <div className="mt-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <button type="submit" className="btn-primary inline-flex items-center justify-center gap-2">
            {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Search className="w-4 h-4" />}
            Search Patients
          </button>
          <span className="text-sm text-muted-foreground">{message}</span>
        </div>
      </form>

      <div className="grid gap-4">
        {results.map((patient) => (
          <div key={patient.id} className="card-medical p-5 rounded-3xl border border-border hover:shadow-md transition-shadow">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <p className="text-lg font-semibold">{patient.fullName}</p>
                <p className="text-sm text-muted-foreground">Patient code: {patient.patientId}</p>
              </div>
              <div className="rounded-2xl bg-primary/10 px-4 py-2 text-primary text-sm font-medium w-fit capitalize">
                {patient.status || 'active'}
              </div>
            </div>

            <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <div>
                <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Phone</p>
                <p className="font-medium">{patient.phone || 'Not available'}</p>
              </div>
              <div>
                <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Ghana Card</p>
                <p className="font-medium">{patient.ghanaCardNumber || 'Not available'}</p>
              </div>
              <div>
                <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Insurance</p>
                <p className="font-medium">{patient.insuranceProvider || 'Self-pay / not recorded'}</p>
              </div>
            </div>

            <div className="mt-5 flex flex-wrap gap-2">
              <Link
                to={`/patients/${patient.id}`}
                className="btn-primary inline-flex items-center gap-2"
              >
                Open Patient Hub
                <ArrowRight className="w-4 h-4" />
              </Link>
              <Link
                to={`/patients/${patient.id}/chat`}
                className="btn-secondary inline-flex items-center gap-2"
              >
                <MessageSquare className="w-4 h-4" />
                Patient Chat
              </Link>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
