import { useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, History } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { RecordList, StatusBadge } from '@/components/records/RecordList';

interface AuditRow {
  id: string;
  action: string;
  changed_at: string;
  changed_by: string | null;
  changed_fields: string[] | null;
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
    const { data, error } = await (supabase as any)
      .from('patient_audit_log')
      .select('id, action, changed_at, changed_by, changed_fields, old_record, new_record')
      .eq('patient_id', patientId)
      .order('changed_at', { ascending: false })
      .limit(100);
    if (error) toast.error(error.message);
    else setRows((data ?? []) as AuditRow[]);
    setLoading(false);
  };

  useEffect(() => { void load(); }, [patientId]);

  const columns = useMemo(() => [
    {
      key: 'action',
      header: 'Action',
      render: (row: AuditRow) => <StatusBadge status={row.action || 'change'} />,
    },
    {
      key: 'changed_at',
      header: 'Changed',
      render: (row: AuditRow) => (
        <time dateTime={row.changed_at} title={new Date(row.changed_at).toLocaleString()}>
          {new Date(row.changed_at).toLocaleString()}
        </time>
      ),
    },
    {
      key: 'changed_by',
      header: 'Actor',
      hideBelow: 'md' as const,
      render: (row: AuditRow) => row.changed_by ?? 'System',
    },
    {
      key: 'changed_fields',
      header: 'Changed fields',
      hideBelow: 'lg' as const,
      render: (row: AuditRow) => row.changed_fields?.length ? row.changed_fields.join(', ') : 'Not specified',
    },
    {
      key: 'snapshot',
      header: 'Snapshot',
      render: (row: AuditRow) => (
        <details className="max-w-xl text-xs" onClick={(event) => event.stopPropagation()}>
          <summary className="cursor-pointer font-medium">View record snapshot</summary>
          <div className="grid gap-3 md:grid-cols-2 mt-3">
            {row.old_record && (
              <div>
                <p className="mb-1 font-medium text-muted-foreground">Previous</p>
                <pre className="overflow-auto rounded-lg bg-muted p-3 max-h-64">{JSON.stringify(row.old_record, null, 2)}</pre>
              </div>
            )}
            {row.new_record && (
              <div>
                <p className="mb-1 font-medium text-muted-foreground">Current</p>
                <pre className="overflow-auto rounded-lg bg-muted p-3 max-h-64">{JSON.stringify(row.new_record, null, 2)}</pre>
              </div>
            )}
          </div>
        </details>
      ),
    },
  ], []);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <Link to={patientId ? `/patients/${patientId}` : '/patients'} className="inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground mb-2">
            <ArrowLeft className="w-4 h-4" /> Back to Patient Hub
          </Link>
          <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
            <History className="w-6 h-6 text-primary" /> Patient Audit History
          </h1>
          <p className="text-muted-foreground">Trace of demographic and administrative patient-record changes.</p>
        </div>
      </div>

      <RecordList
        title="Audit history"
        description={`${rows.length} recorded change(s)`}
        data={rows}
        columns={columns}
        isLoading={loading}
        error={null}
        rowKey={(row) => row.id}
        onRefresh={() => void load()}
        emptyState={{
          title: 'No patient-record changes',
          description: 'No demographic or administrative changes have been recorded for this patient.',
        }}
      />
    </div>
  );
}
