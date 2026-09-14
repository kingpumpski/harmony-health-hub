import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, History, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface AuditRow {
  id: string;
  operation: string;
  occurred_at: string;
  actor_user_id: string | null;
  changed_fields: Record<string, { old?: unknown; new?: unknown }> | null;
  old_record: Record<string, unknown> | null;
  new_record: Record<string, unknown> | null;
}

export default function PatientAudit() {
  const { patientId } = useParams<{ patientId: string }>();
  const [rows, setRows] = useState<AuditRow[]>([]);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    if (!patientId) return;
    setLoading(true);
    const { data, error } = await supabase
      .from('patient_audit')
      .select('id, operation, occurred_at, actor_user_id, changed_fields, old_record, new_record')
      .eq('patient_id', patientId)
      .order('occurred_at', { ascending: false })
      .limit(100);

    if (error) {
      toast.error(error.message);
    } else {
      setRows((data ?? []) as AuditRow[]);
    }
    setLoading(false);
  };

  useEffect(() => {
    void load();
  }, [patientId]);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <Link
            to={patientId ? `/patients/${patientId}` : '/patients'}
            className="inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground mb-2"
          >
            <ArrowLeft className="w-4 h-4" /> Back to Patient Hub
          </Link>
          <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
            <History className="w-6 h-6 text-primary" /> Patient Audit History
          </h1>
          <p className="text-muted-foreground">Trace of demographic and administrative patient-record changes.</p>
        </div>
        <button onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2">
          <RefreshCw className="w-4 h-4" /> Refresh
        </button>
      </div>

      <div className="card-medical p-5">
        {loading ? (
          <p className="text-sm text-muted-foreground">Loading audit history…</p>
        ) : rows.length === 0 ? (
          <p className="text-sm text-muted-foreground">No patient-record changes have been recorded.</p>
        ) : (
          <div className="space-y-3">
            {rows.map((row) => {
              const changedFields = Object.keys(row.changed_fields ?? {});
              return (
                <article key={row.id} className="rounded-xl border border-border p-4">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <span className="text-xs font-semibold rounded-full bg-primary/10 text-primary px-2 py-1">
                        {row.operation}
                      </span>
                      <span className="text-sm">{new Date(row.occurred_at).toLocaleString()}</span>
                    </div>
                    <span className="text-xs text-muted-foreground">Actor: {row.actor_user_id ?? 'System'}</span>
                  </div>
                  {changedFields.length ? (
                    <p className="mt-2 text-xs text-muted-foreground">
                      Changed fields: {changedFields.join(', ')}
                    </p>
                  ) : null}
                  <details className="mt-3 text-xs">
                    <summary className="cursor-pointer font-medium">View record snapshot</summary>
                    <div className="grid gap-3 md:grid-cols-2 mt-3">
                      {row.old_record && (
                        <pre className="overflow-auto rounded-lg bg-muted p-3 max-h-64">
                          {JSON.stringify(row.old_record, null, 2)}
                        </pre>
                      )}
                      {row.new_record && (
                        <pre className="overflow-auto rounded-lg bg-muted p-3 max-h-64">
                          {JSON.stringify(row.new_record, null, 2)}
                        </pre>
                      )}
                    </div>
                  </details>
                </article>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
