import { useCallback, useEffect, useState } from 'react';
import { Activity, AlertTriangle, ListChecks, Plus, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import TriageRecordForm from '@/components/triage/TriageRecordForm';

type Patient = { id: string; patient_code: string | null; first_name: string; last_name: string };
type TriageRow = {
  id: string;
  patient_id: string;
  priority: string;
  systolic: number | null;
  diastolic: number | null;
  temperature: number | null;
  oxygen_saturation: number | null;
  bmi: number | null;
  created_at: string;
  patients?: { first_name: string; last_name: string } | null;
};

export default function Triage() {
  const [patients, setPatients] = useState<Patient[]>([]);
  const [history, setHistory] = useState<TriageRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showForm, setShowForm] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    const [patientResponse, triageResponse] = await Promise.all([
      supabase.from('patients').select('id, patient_code, first_name, last_name').order('created_at', { ascending: false }).limit(500),
      (supabase as any).from('triage_assessments')
        .select('id, patient_id, priority, systolic, diastolic, temperature, oxygen_saturation, bmi, created_at, patients(first_name,last_name)')
        .order('created_at', { ascending: false })
        .limit(100),
    ]);
    if (patientResponse.error || triageResponse.error) {
      setError('Unable to load triage records. Retry.');
      setPatients([]);
      setHistory([]);
    } else {
      setPatients((patientResponse.data ?? []) as Patient[]);
      setHistory((triageResponse.data ?? []) as TriageRow[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const criticalCount = history.filter((row) => row.priority === 'critical').length;
  const urgentCount = history.filter((row) => row.priority === 'urgent').length;

  return (
    <OperationalWorklistShell
      icon={Activity}
      eyebrow="Clinical assessment"
      title="Triage & Vital Signs"
      description="Review recent triage records and add a new patient assessment."
      counters={[
        { label: 'Recent assessments', value: history.length },
        { label: 'Critical', value: criticalCount, tone: 'text-critical' },
        { label: 'Urgent', value: urgentCount, tone: 'text-warning' },
        { label: 'Routine', value: Math.max(0, history.length - criticalCount - urgentCount) },
      ]}
      beforeList={
        <section className="card-medical p-5">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 className="font-semibold">Triage records</h2>
              <p className="text-xs text-muted-foreground">Select a patient from the list or open a patient chart for the full graphical history.</p>
            </div>
            <button type="button" onClick={() => setShowForm((value) => !value)} className="btn-primary inline-flex items-center justify-center gap-2">
              <Plus className="h-4 w-4" /> {showForm ? 'Close form' : 'Add Record'}
            </button>
          </div>
          {showForm && <div className="mt-5 rounded-2xl border border-primary/20 bg-primary/5 p-4"><TriageRecordForm patients={patients} onSaved={() => { setShowForm(false); void load(); }} onCancel={() => setShowForm(false)} /></div>}
        </section>
      }
      listTitle="Recent patient triage"
      listDescription="Patient name, measured observations, priority and recording time are shown without internal identifiers."
      listMeta={loading ? 'Loading…' : `${history.length} record${history.length === 1 ? '' : 's'}`}
      empty={!loading && !error && history.length === 0}
      emptyIcon={ListChecks}
      emptyTitle="No triage records yet"
      emptyDescription="Use Add Record to enter the first triage assessment."
    >
      {loading && <div className="space-y-3 p-4" role="status" aria-label="Loading triage records"><div className="h-5 w-48 animate-pulse rounded bg-muted" /><div className="h-16 animate-pulse rounded-xl bg-muted" /><div className="h-16 animate-pulse rounded-xl bg-muted" /></div>}
      {!loading && error && <div className="m-4 rounded-xl border border-destructive/30 bg-destructive/5 p-4" role="alert"><p className="text-sm font-medium">{error}</p><button type="button" onClick={() => void load()} className="btn-secondary mt-3 inline-flex items-center gap-2"><RefreshCw className="h-4 w-4" />Retry</button></div>}
      {!loading && !error && history.map((row) => (
        <div key={row.id} className="flex flex-col gap-3 border-b p-4 last:border-0 sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0">
            <p className="truncate font-medium">{row.patients?.first_name ?? 'Patient'} {row.patients?.last_name ?? ''}</p>
            <p className="mt-1 text-xs text-muted-foreground">BP {row.systolic ?? '—'}/{row.diastolic ?? '—'} · Temp {row.temperature ?? '—'}°C · SpO₂ {row.oxygen_saturation ?? '—'}% · BMI {row.bmi ?? '—'}</p>
          </div>
          <div className="flex items-center gap-3 text-xs">
            <span className={`rounded-full px-2.5 py-1 font-semibold ${row.priority === 'critical' ? 'bg-critical/10 text-critical' : row.priority === 'urgent' ? 'bg-warning/10 text-warning' : 'bg-muted text-muted-foreground'}`}>{row.priority}</span>
            <span className="text-muted-foreground">{new Date(row.created_at).toLocaleString()}</span>
          </div>
        </div>
      ))}
      {!loading && !error && history.length > 0 && <div className="border-t p-4"><div className="flex gap-2 rounded-xl border border-warning/20 bg-warning/5 p-3 text-xs text-muted-foreground"><AlertTriangle className="h-4 w-4 shrink-0 text-warning" /> Reference ranges are contextual clinical aids and do not replace clinician interpretation.</div></div>}
    </OperationalWorklistShell>
  );
}
