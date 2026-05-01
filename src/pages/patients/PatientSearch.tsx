import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Search, Loader2, UserPlus, Zap, MessageSquare } from 'lucide-react';
import { searchPatients } from '@/lib/healthApi';

export default function PatientSearch() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState('Type a name, ID, or phone number to search patients.');

  const handleSearch = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!query.trim()) return;
    setIsLoading(true);
    const items = await searchPatients(query.trim());
    setResults(items);
    setIsLoading(false);
    setMessage(items.length ? `${items.length} patient(s) found.` : 'No matching patients found.');
  };

  const activeLabel = useMemo(() => (results.length ? 'Elasticsearch results' : 'Quick search'), [results.length]);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Patient Search</h1>
          <p className="text-muted-foreground">Elasticsearch-powered search for fast patient lookup.</p>
        </div>
        <div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3">
          <Zap className="w-5 h-5 text-primary" />
          <span className="text-sm text-muted-foreground">Search across patient records, IDs, phone numbers and Ghana Card data.</span>
        </div>
      </div>

      <form onSubmit={handleSearch} className="card-medical p-6">
        <div className="relative">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search patients by name, Client ID, Ghana Card or phone number"
            className="input-medical pl-12 w-full"
          />
        </div>
        <div className="mt-4 flex items-center justify-between gap-3">
          <button type="submit" className="btn-primary inline-flex items-center gap-2">
            {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Search className="w-4 h-4" />}
            Search
          </button>
          <span className="text-sm text-muted-foreground">{message}</span>
        </div>
      </form>

      <div className="grid gap-4">
        {results.map((patient) => (
          <div key={patient.patientId} className="card-medical p-5 rounded-3xl border border-border hover:shadow-md transition-shadow">
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-lg font-semibold">{patient.fullName || `${patient.firstName} ${patient.lastName}`}</p>
                <p className="text-sm text-muted-foreground">Client ID: {patient.patientId}</p>
              </div>
              <div className="rounded-2xl bg-primary/10 px-4 py-2 text-primary text-sm font-medium">
                {patient.status || 'active'}
              </div>
            </div>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              <div>
                <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Phone</p>
                <p className="font-medium">{patient.phone}</p>
              </div>
              <div>
                <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">Ghana Card</p>
                <p className="font-medium">{patient.ghanaCardNumber || 'Not available'}</p>
              </div>
            </div>
            <div className="mt-4 flex flex-wrap gap-2">
              <Link
                to={`/patients/${patient.patientId}/chat`}
                className="btn-secondary inline-flex items-center gap-2"
              >
                <MessageSquare className="w-4 h-4" />
                Open Patient Chat
              </Link>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
