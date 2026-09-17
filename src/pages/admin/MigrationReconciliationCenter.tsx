import { useEffect, useMemo, useState } from 'react';
import { CheckCircle2, ClipboardCheck, Database, FileWarning, RefreshCw, Search } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

interface Batch {
  id: string;
  entity_type: string;
  source_system: string;
  source_version: string | null;
  file_name: string | null;
  total_rows: number;
  staged_rows: number;
  accepted_rows: number;
  rejected_rows: number;
  status: string;
  created_at: string;
}

interface MigrationRow {
  id: string;
  source_row_number: number;
  source_key: string | null;
  raw_data: Record<string, unknown>;
  normalized_data: Record<string, unknown> | null;
  row_status: string;
  rejection_reason: string | null;
  target_table: string | null;
  target_id: string | null;
}

interface LegacyRecord {
  id: string;
  patient_id: string | null;
  source_system: string;
  source_patient_key: string | null;
  source_record_id: string | null;
  record_type: string;
  occurred_at: string | null;
  department: string | null;
  migration_status: string;
  clinical_summary: string | null;
}

const statusClass: Record<string, string> = {
  completed: 'bg-success/10 text-success',
  completed_with_errors: 'bg-warning/10 text-warning',
  ready: 'bg-primary/10 text-primary',
  validating: 'bg-info/10 text-info',
  rejected: 'bg-critical/10 text-critical',
  needs_review: 'bg-warning/10 text-warning',
};

export default function MigrationReconciliationCenter() {
  const [batches, setBatches] = useState<Batch[]>([]);
  const [selectedBatch, setSelectedBatch] = useState<Batch | null>(null);
  const [rows, setRows] = useState<MigrationRow[]>([]);
  const [legacyRecords, setLegacyRecords] = useState<LegacyRecord[]>([]);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    const [{ data: batchData, error: batchError }, { data: legacyData, error: legacyError }] = await Promise.all([
      supabase
        .from('data_migration_batches')
        .select('id, entity_type, source_system, source_version, file_name, total_rows, staged_rows, accepted_rows, rejected_rows, status, created_at')
        .order('created_at', { ascending: false })
        .limit(100),
      supabase
        .from('legacy_clinical_records')
        .select('id, patient_id, source_system, source_patient_key, source_record_id, record_type, occurred_at, department, migration_status, clinical_summary')
        .order('created_at', { ascending: false })
        .limit(100),
    ]);
    setLoading(false);
    if (batchError || legacyError) {
      toast({
        title: 'Migration workspace could not load',
        description: batchError?.message || legacyError?.message,
        variant: 'destructive',
      });
      return;
    }
    setBatches((batchData ?? []) as Batch[]);
    setLegacyRecords((legacyData ?? []) as LegacyRecord[]);
  };

  const loadRows = async (batch: Batch) => {
    setSelectedBatch(batch);
    const { data, error } = await supabase
      .from('data_migration_rows')
      .select('id, source_row_number, source_key, raw_data, normalized_data, row_status, rejection_reason, target_table, target_id')
      .eq('batch_id', batch.id)
      .order('source_row_number', { ascending: true })
      .limit(500);
    if (error) {
      toast({ title: 'Migration rows unavailable', description: error.message, variant: 'destructive' });
      return;
    }
    setRows((data ?? []) as MigrationRow[]);
  };

  useEffect(() => { void load(); }, []);

  const filteredLegacy = useMemo(() => {
    const term = search.trim().toLowerCase();
    if (!term) return legacyRecords;
    return legacyRecords.filter((record) =>
      [record.source_patient_key, record.source_record_id, record.record_type, record.department, record.clinical_summary]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(term)),
    );
  }, [legacyRecords, search]);

  const batchSummary = useMemo(() => {
    return batches.reduce((summary, batch) => {
      summary.total += batch.total_rows;
      summary.staged += batch.staged_rows;
      summary.accepted += batch.accepted_rows;
      summary.rejected += batch.rejected_rows;
      return summary;
    }, { total: 0, staged: 0, accepted: 0, rejected: 0 });
  }, [batches]);

  return (
    <div className="space-y-6 animate-fade-in">
      <header className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
            <ClipboardCheck className="w-6 h-6 text-primary" /> Migration Reconciliation Center
          </h1>
          <p className="text-muted-foreground">
            Review imported master data and legacy clinical records before any native clinical promotion.
          </p>
        </div>
        <button type="button" onClick={() => void load()} disabled={loading} className="btn-ghost inline-flex items-center gap-2">
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} /> Refresh
        </button>
      </header>

      <div className="grid gap-4 md:grid-cols-4">
        {[
          ['Batches', batches.length, Database],
          ['Source rows', batchSummary.total, Database],
          ['Accepted', batchSummary.accepted, CheckCircle2],
          ['Rejected', batchSummary.rejected, FileWarning],
        ].map(([label, value, Icon]) => {
          const IconComponent = Icon as typeof Database;
          return (
            <section key={String(label)} className="card-medical p-4">
              <div className="flex items-center gap-2 text-xs text-muted-foreground"><IconComponent className="w-4 h-4" /> {label}</div>
              <strong className="block text-2xl mt-2">{String(value)}</strong>
            </section>
          );
        })}
      </div>

      <div className="grid gap-6 xl:grid-cols-[minmax(320px,420px)_minmax(0,1fr)]">
        <section className="card-medical p-5">
          <h2 className="font-semibold mb-3">Migration batches</h2>
          <div className="space-y-2 max-h-[640px] overflow-auto">
            {batches.map((batch) => (
              <button
                key={batch.id}
                type="button"
                onClick={() => void loadRows(batch)}
                className={`w-full rounded-xl border p-3 text-left ${selectedBatch?.id === batch.id ? 'border-primary bg-primary/5' : 'border-border hover:bg-accent/30'}`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-medium text-sm">{batch.entity_type}</p>
                    <p className="text-xs text-muted-foreground">{batch.source_system}{batch.source_version ? ` · ${batch.source_version}` : ''}</p>
                  </div>
                  <span className={`rounded-full px-2 py-1 text-[11px] ${statusClass[batch.status] || 'bg-muted text-muted-foreground'}`}>{batch.status}</span>
                </div>
                <p className="text-xs mt-2">{batch.staged_rows}/{batch.total_rows} staged · {batch.accepted_rows} accepted · {batch.rejected_rows} rejected</p>
                <p className="text-[11px] text-muted-foreground mt-1">{new Date(batch.created_at).toLocaleString()}</p>
              </button>
            ))}
            {batches.length === 0 && <p className="text-sm text-muted-foreground">No migration batches have been staged.</p>}
          </div>
        </section>

        <section className="card-medical p-5 min-w-0">
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 className="font-semibold">Row reconciliation preview</h2>
              <p className="text-xs text-muted-foreground">Imported rows remain staged until validation and controlled promotion are implemented.</p>
            </div>
            {selectedBatch && <span className="text-xs rounded-full bg-muted px-2 py-1">{selectedBatch.entity_type}</span>}
          </div>
          {!selectedBatch ? (
            <div className="py-16 text-center text-muted-foreground">Select a migration batch to inspect its rows.</div>
          ) : (
            <div className="mt-4 space-y-2 max-h-[640px] overflow-auto">
              {rows.map((row) => (
                <article key={row.id} className="rounded-xl border border-border p-3">
                  <div className="flex flex-wrap justify-between gap-2 text-xs">
                    <span>Row {row.source_row_number}{row.source_key ? ` · ${row.source_key}` : ''}</span>
                    <span className={`rounded-full px-2 py-1 ${statusClass[row.row_status] || 'bg-muted text-muted-foreground'}`}>{row.row_status}</span>
                  </div>
                  {row.rejection_reason && <p className="text-xs text-critical mt-2">{row.rejection_reason}</p>}
                  <pre className="mt-2 overflow-auto rounded-lg bg-muted p-3 text-[11px]">{JSON.stringify(row.normalized_data ?? row.raw_data, null, 2)}</pre>
                  {row.target_table && <p className="text-[11px] text-muted-foreground mt-2">Target: {row.target_table}{row.target_id ? ` · ${row.target_id}` : ''}</p>}
                </article>
              ))}
              {rows.length === 0 && <p className="text-sm text-muted-foreground">This batch has no staged rows.</p>}
            </div>
          )}
        </section>
      </div>

      <section className="card-medical p-5">
        <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div>
            <h2 className="font-semibold">Legacy clinical record continuity queue</h2>
            <p className="text-xs text-muted-foreground">Use source identifiers and clinical chronology for patient matching before native-record promotion.</p>
          </div>
          <label className="relative block md:w-80">
            <Search className="absolute left-3 top-2.5 w-4 h-4 text-muted-foreground" />
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search source patient, record or department" className="input-medical w-full pl-9" />
          </label>
        </div>
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-sm">
            <thead><tr className="border-b border-border text-left text-xs text-muted-foreground"><th className="p-2">Source</th><th className="p-2">Patient key</th><th className="p-2">Record</th><th className="p-2">Occurred</th><th className="p-2">Department</th><th className="p-2">Status</th></tr></thead>
            <tbody>
              {filteredLegacy.map((record) => (
                <tr key={record.id} className="border-b border-border/70 align-top">
                  <td className="p-2">{record.source_system}</td>
                  <td className="p-2 font-medium">{record.source_patient_key || '—'}</td>
                  <td className="p-2"><div>{record.record_type}</div><div className="text-[11px] text-muted-foreground">{record.source_record_id || 'No source record ID'}</div>{record.clinical_summary && <div className="text-xs mt-1 max-w-xl">{record.clinical_summary}</div>}</td>
                  <td className="p-2 whitespace-nowrap">{record.occurred_at ? new Date(record.occurred_at).toLocaleString() : '—'}</td>
                  <td className="p-2">{record.department || '—'}</td>
                  <td className="p-2"><span className={`rounded-full px-2 py-1 text-[11px] ${statusClass[record.migration_status] || 'bg-muted text-muted-foreground'}`}>{record.migration_status}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
          {filteredLegacy.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">No legacy records match the current search.</p>}
        </div>
      </section>
    </div>
  );
}
