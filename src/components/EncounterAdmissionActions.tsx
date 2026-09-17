import { useCallback, useEffect, useState } from 'react';
import { BedDouble, CheckCircle2, Loader2, ShieldAlert } from 'lucide-react';
import { useLocation } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

type EncounterRow = {
  id: string;
  patient_id: string;
  status: string;
  created_at: string;
  principal_diagnosis: string | null;
  admission_id: string | null;
};

type PatientRow = {
  id: string;
  first_name: string;
  last_name: string;
  patient_code: string;
};

const db = supabase as any;

export default function EncounterAdmissionActions() {
  const location = useLocation();
  const [rows, setRows] = useState<EncounterRow[]>([]);
  const [patients, setPatients] = useState<PatientRow[]>([]);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (location.pathname !== '/encounters') return;
    const [{ data: encounters, error: encounterError }, { data: patientRows, error: patientError }] = await Promise.all([
      db.from('encounters')
        .select('id,patient_id,status,created_at,principal_diagnosis,admission_id')
        .eq('status', 'completed')
        .is('admission_id', null)
        .order('created_at', { ascending: false })
        .limit(12),
      db.from('patients')
        .select('id,first_name,last_name,patient_code')
        .order('created_at', { ascending: false })
        .limit(300),
    ]);
    if (encounterError) {
      toast.error(`Admission queue unavailable: ${encounterError.message}`);
      return;
    }
    if (patientError) {
      toast.error(`Patient details unavailable: ${patientError.message}`);
      return;
    }
    setRows((encounters ?? []) as EncounterRow[]);
    setPatients((patientRows ?? []) as PatientRow[]);
  }, [location.pathname]);

  useEffect(() => {
    void load();
  }, [load]);

  if (location.pathname !== '/encounters' || rows.length === 0) return null;

  const admit = async (encounter: EncounterRow) => {
    setBusy(encounter.id);
    const { data, error } = await db.rpc('admit_encounter_workflow', {
      _encounter_id: encounter.id,
      _reason: 'Clinical admission from completed encounter',
      _ward: null,
      _emergency_override: true,
    });
    setBusy(null);
    if (error) {
      toast.error(`Admission failed: ${error.message}`);
      return;
    }
    const override = Boolean(data?.override);
    toast.success(override
      ? 'Patient admitted. Facility emergency treatment override is active; Accounts remains responsible for subsequent financial clearance.'
      : 'Patient admitted successfully.');
    await load();
  };

  return (
    <aside className="fixed bottom-4 right-4 z-40 w-[min(420px,calc(100vw-2rem))] rounded-2xl border border-border bg-card/95 p-4 shadow-xl backdrop-blur">
      <div className="flex items-start gap-3">
        <div className="rounded-xl bg-primary/10 p-2 text-primary"><BedDouble className="h-5 w-5" /></div>
        <div className="min-w-0 flex-1">
          <h2 className="font-semibold">Completed encounters ready for admission</h2>
          <p className="mt-1 text-xs text-muted-foreground">Admission is server-authorized. If facility emergency override is enabled, eligible pending services can be released before deposit and audited.</p>
        </div>
      </div>
      <div className="mt-3 max-h-64 space-y-2 overflow-auto">
        {rows.map((encounter) => {
          const patient = patients.find((item) => item.id === encounter.patient_id);
          return (
            <div key={encounter.id} className="rounded-xl border border-border bg-background p-3">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{patient ? `${patient.first_name} ${patient.last_name}` : 'Patient'}</p>
                  <p className="text-[11px] text-muted-foreground">{patient?.patient_code ?? 'Patient record'} · {new Date(encounter.created_at).toLocaleString()}</p>
                  {encounter.principal_diagnosis && <p className="mt-1 truncate text-xs">Dx: {encounter.principal_diagnosis}</p>}
                </div>
                <button type="button" disabled={busy !== null} onClick={() => void admit(encounter)} className="btn-primary shrink-0 inline-flex items-center gap-1.5 text-xs">
                  {busy === encounter.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CheckCircle2 className="h-3.5 w-3.5" />}
                  Admit
                </button>
              </div>
            </div>
          );
        })}
      </div>
      <div className="mt-3 flex items-start gap-2 rounded-lg bg-warning/10 p-2 text-[11px] text-muted-foreground">
        <ShieldAlert className="mt-0.5 h-3.5 w-3.5 shrink-0 text-warning" />
        <span>Emergency override never represents payment received. Accounts must complete the normal payment/release workflow for later services and financial reconciliation.</span>
      </div>
    </aside>
  );
}
