import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { FileText, Search, UserRound } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Patient { id: string; patient_code: string; first_name: string; last_name: string; phone: string | null; status: string | null }

export default function MedicalRecords() {
  const [patients, setPatients] = useState<Patient[]>([]);
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      const { data, error } = await supabase.from('patients').select('id, patient_code, first_name, last_name, phone, status').order('created_at', { ascending: false }).limit(300);
      if (error) toast.error(error.message); else setPatients((data ?? []) as Patient[]);
      setLoading(false);
    };
    void load();
  }, []);

  const filtered = patients.filter((patient) => {
    const haystack = `${patient.first_name} ${patient.last_name} ${patient.patient_code} ${patient.phone ?? ''}`.toLowerCase();
    return haystack.includes(query.trim().toLowerCase());
  });

  return <div className="space-y-6 animate-fade-in">
    <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><FileText className="w-6 h-6 text-primary" /> Medical Records</h1><p className="text-muted-foreground">Open a patient chart and review the complete clinical record.</p></div>
    <div className="card-medical p-4 flex items-center gap-3"><Search className="w-5 h-5 text-muted-foreground" /><input value={query} onChange={(e) => setQuery(e.target.value)} className="input-medical flex-1" placeholder="Search by patient name, code or phone…" /></div>
    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
      {filtered.map((patient) => <Link key={patient.id} to={`/patients/${patient.id}`} className="card-medical p-5 hover:border-primary/50 transition-colors"><div className="flex items-start gap-3"><div className="rounded-xl bg-primary/10 p-2"><UserRound className="w-5 h-5 text-primary" /></div><div className="min-w-0"><p className="font-semibold truncate">{patient.first_name} {patient.last_name}</p><p className="text-xs text-muted-foreground">{patient.patient_code} · {patient.status ?? 'active'}</p><p className="text-sm text-muted-foreground mt-2">{patient.phone || 'No phone recorded'}</p></div></div></Link>)}
    </div>
    {!loading && filtered.length === 0 && <p className="text-sm text-muted-foreground text-center py-8">No matching patient records.</p>}
    {loading && <p className="text-sm text-muted-foreground">Loading records…</p>}
  </div>;
}
