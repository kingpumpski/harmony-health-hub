import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { useEffect, useState } from 'react';
import Papa from 'papaparse';
import { Database, FileSpreadsheet, Upload, AlertTriangle, ShieldCheck, RefreshCw, UserCheck, CheckCircle2, Search } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { notifyMasterDataChanged } from '@/lib/masterDataEvents';

type Entity = 'patients' | 'pharmacy_inventory' | 'icd_codes' | 'stg_diagnoses' | 'service_tariffs' | 'legacy_clinical_records';
type Row = Record<string, string | number | boolean | null>;
type MigrationBatch = { id: string; entity_type: string; source_system: string; source_version: string | null; file_name: string | null; total_rows: number; staged_rows: number; accepted_rows: number; rejected_rows: number; status: string; created_at: string; approved_at: string | null; completed_at: string | null };
type MigrationRow = { id: string; source_row_number: number; source_key: string | null; raw_data: Record<string, unknown>; row_status: string; patient_id: string | null; match_confidence: number | null; match_method: string | null; validation_errors: string[]; rejection_reason: string | null };
type PatientCandidate = { patient_id: string; patient_code: string; first_name: string; last_name: string; date_of_birth: string | null; phone: string | null; email: string | null; method: string; confidence: number };
const MAX_FILE_BYTES = 25 * 1024 * 1024;
const MAX_ROWS = 10_000;
const PREVIEW_ROWS = 10;

const schemas: Record<Entity, { label: string; required: string[]; description: string }> = {
  patients: { label: 'Patients', required: ['first_name', 'last_name'], description: 'Patient demographic and registration data.' },
  pharmacy_inventory: { label: 'Pharmacy inventory', required: ['drug_name'], description: 'Opening stock and medicine master data.' },
  icd_codes: { label: 'ICD-10 codes', required: ['code', 'description'], description: 'ICD-10 reference data.' },
  stg_diagnoses: { label: 'Ghana STG diagnoses', required: ['code', 'display_name'], description: 'Ghana Standard Treatment Guidelines diagnosis/reference data. Current/licensed source files should be supplied by the facility.' },
  service_tariffs: { label: 'Services & tariffs', required: ['service_code', 'service_name', 'amount'], description: 'Billable services, departments, units and GHS tariffs used by orders and billing.' },
  legacy_clinical_records: { label: 'Legacy clinical records', required: ['source_system', 'source_patient_key', 'record_type'], description: 'Continuity-of-care records staged for reconciliation instead of being blindly inserted into clinical tables.' },
};

const templateHeaders: Record<Entity, string[]> = {
  patients: ['patient_code','first_name','last_name','date_of_birth','gender','phone','email','address','ghana_card_number','blood_group','genotype','allergies','chronic_conditions','insurance_provider','insurance_number'],
  pharmacy_inventory: ['drug_name','generic_name','strength','form','stock_quantity','reorder_level','unit_price','supplier','expiry_date'],
  icd_codes: ['code','description','version','category'],
  stg_diagnoses: ['code','display_name','description','category','synonyms','source_reference','is_active'],
  service_tariffs: ['service_code','service_name','department','unit','amount','currency','effective_from','effective_to','active','metadata'],
  legacy_clinical_records: ['source_system','source_version','source_patient_key','source_record_id','record_type','occurred_at','author_name','department','encounter_reference','clinical_summary','raw_record'],
};

const normalize = (value: unknown): string | number | boolean | null => {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value === 'boolean' || typeof value === 'number') return value;
  return String(value).trim();
};
const normalizeRows = (data: Array<Record<string, unknown>>): Row[] => data.map((row) => Object.fromEntries(Object.entries(row).map(([key, value]) => [key.trim().toLowerCase(), normalize(value)])));

export default function DataImport() {
  const { user } = useAuth();
  const [entity, setEntity] = useState<Entity>('patients');
  const [rows, setRows] = useState<Row[]>([]);
  const [fileName, setFileName] = useState('');
  const [busy, setBusy] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [sourceSystem, setSourceSystem] = useState('Legacy system');
  const [sourceVersion, setSourceVersion] = useState('');
  const [batches, setBatches] = useState<MigrationBatch[]>([]);
  const [selectedBatch, setSelectedBatch] = useState<string | null>(null);
  const [migrationRows, setMigrationRows] = useState<MigrationRow[]>([]);
  const [candidates, setCandidates] = useState<Record<string, PatientCandidate[]>>({});
  const [migrationBusy, setMigrationBusy] = useState<string | null>(null);

  const refreshBatches = async () => {
    if (user?.role !== 'admin') return;
    const { data: workspace, error } = await getOperationalWorkspace('data_migration', 20); const data = (workspace as any)?.batches ?? [];
    if (error) return toast({ title: 'Migration workspace unavailable', description: error.message, variant: 'destructive' });
    setBatches((data ?? []) as MigrationBatch[]);
  };

  const loadRows = async (batchId: string) => {
    setSelectedBatch(batchId);
    setCandidates({});
    const { data, error } = await supabase.from('data_migration_rows').select('id,source_row_number,source_key,raw_data,row_status,patient_id,match_confidence,match_method,validation_errors,rejection_reason').eq('batch_id', batchId).order('source_row_number').limit(100);
    if (error) return toast({ title: 'Could not load migration rows', description: error.message, variant: 'destructive' });
    setMigrationRows((data ?? []) as MigrationRow[]);
  };

  useEffect(() => { void refreshBatches(); }, [user?.id, user?.role]);

  if (user?.role !== 'admin') return <div className="p-8 text-center"><AlertTriangle className="w-10 h-10 text-warning mx-auto mb-2" /><h2 className="font-semibold text-xl">Admin only</h2><p className="text-muted-foreground">Bulk database and migration imports require administrator access.</p></div>;

  const parse = async (file: File) => {
    setFileName(''); setRows([]); setErrors([]);
    if (file.size > MAX_FILE_BYTES) return toast({ title: 'File too large', description: `Imports are limited to ${MAX_FILE_BYTES / 1024 / 1024} MB.`, variant: 'destructive' });
    const lowerName = file.name.toLowerCase();
    if (!lowerName.endsWith('.csv') && !lowerName.endsWith('.xlsx') && !lowerName.endsWith('.xls')) return toast({ title: 'Unsupported file', description: 'Choose CSV, XLSX or XLS.', variant: 'destructive' });
    setFileName(file.name);
    if (lowerName.endsWith('.csv')) {
      Papa.parse<Record<string, unknown>>(file, { header: true, skipEmptyLines: true, transformHeader: (header) => header.trim().toLowerCase(), complete: (result) => {
        if (result.errors.length) { setFileName(''); return toast({ title: 'CSV parse failed', description: result.errors[0].message, variant: 'destructive' }); }
        if (result.data.length > MAX_ROWS) { setFileName(''); return toast({ title: 'Too many rows', description: `Imports are limited to ${MAX_ROWS.toLocaleString()} rows.`, variant: 'destructive' }); }
        setRows(normalizeRows(result.data));
      }, error: (error) => { setFileName(''); toast({ title: 'CSV parse failed', description: error.message, variant: 'destructive' }); } });
      return;
    }
    try {
      const XLSX = await import('xlsx');
      const workbook = XLSX.read(await file.arrayBuffer(), { type: 'array', dense: true, cellFormula: false });
      const sheetName = workbook.SheetNames[0]; if (!sheetName) throw new Error('The workbook contains no worksheets.');
      const data = XLSX.utils.sheet_to_json<Record<string, unknown>>(workbook.Sheets[sheetName], { defval: null, raw: true });
      if (data.length > MAX_ROWS) throw new Error(`Imports are limited to ${MAX_ROWS.toLocaleString()} rows.`);
      setRows(normalizeRows(data));
    } catch (error) { setFileName(''); toast({ title: 'Spreadsheet parse failed', description: error instanceof Error ? error.message : 'Invalid workbook.', variant: 'destructive' }); }
  };

  const validate = (row: Row, index: number) => {
    for (const field of schemas[entity].required) if (row[field] === null || row[field] === undefined || String(row[field]).trim() === '') return `Row ${index + 2}: missing ${field}`;
    if (entity === 'patients' && row.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(row.email))) return `Row ${index + 2}: invalid email`;
    if (entity === 'service_tariffs' && Number(row.amount) < 0) return `Row ${index + 2}: tariff amount cannot be negative`;
    return null;
  };

  const importRows = async () => {
    if (!rows.length || !user?.id || busy) return;
    setBusy(true); const failed: string[] = []; let inserted = 0;
    try {
      const validationErrors = rows.map(validate).filter(Boolean) as string[];
      if (validationErrors.length) failed.push(...validationErrors);
      const validRows = rows.filter((row, index) => !validate(row, index));
      if (!validRows.length) throw new Error('No valid rows remain after validation.');

      if (entity === 'stg_diagnoses') {
        const { data, error } = await supabase.rpc('import_stg_diagnoses' as never, { _standard_code: 'GH-STG', _source_version: sourceVersion || null, _rows: validRows.map((row) => ({ ...row, synonyms: row.synonyms ? String(row.synonyms).split(/[|,;]/).map((v) => v.trim()).filter(Boolean) : [] })) } as never);
        if (error) throw error; inserted = Number(data ?? 0);
      } else if (entity === 'service_tariffs') {
        const { data, error } = await supabase.rpc('import_service_tariffs' as never, { _source_standard: sourceSystem || 'Facility tariff', _rows: validRows } as never);
        if (error) throw error; inserted = Number(data ?? 0);
      } else if (entity === 'legacy_clinical_records') {
        const { data: batch, error: batchError } = await supabase.rpc('create_data_migration_batch' as never, { _entity_type: 'legacy_clinical_records', _source_system: sourceSystem, _source_version: sourceVersion || null, _file_name: fileName || null, _source_format: fileName.toLowerCase().endsWith('.csv') ? 'csv' : 'xlsx', _total_rows: validRows.length } as never);
        if (batchError) throw batchError;
        const { data, error } = await supabase.rpc('stage_data_migration_rows' as never, { _batch_id: batch, _rows: validRows } as never);
        if (error) throw error;
        inserted = Number(data ?? 0);
        toast({ title: 'Legacy records staged', description: `${inserted} records are ready for patient matching and controlled migration. No native clinical table was modified.` });
        await refreshBatches();
      } else {
        const { data, error } = await supabase.functions.invoke('admin-bulk-import', {
          body: { action: 'import_rows', entity, filename: fileName, rows: validRows },
        });
        if (error || data?.error) throw new Error(data?.error ?? error?.message ?? 'Server import rejected');
        inserted = Number(data?.inserted_rows ?? 0);
        failed.push(...((data?.errors ?? []) as { row: number; reason: string }[]).map((item) => 'Row ' + item.row + ': ' + item.reason));
      }
    } catch (error) { failed.push(error instanceof Error ? error.message : 'Import failed'); }
    if (inserted > 0) notifyMasterDataChanged(entity === 'service_tariffs' ? 'tariffs' : entity === 'patients' ? 'patients' : entity === 'pharmacy_inventory' ? 'pharmacy' : entity === 'icd_codes' || entity === 'stg_diagnoses' ? 'diagnoses' : 'all');
    setErrors(failed); setBusy(false); setRows([]); setFileName('');
    toast({ title: failed.length ? 'Import completed with issues' : 'Import complete', description: `${inserted}/${rows.length} rows processed${failed.length ? `; ${failed.length} issues recorded` : ''}.`, variant: failed.length && inserted === 0 ? 'destructive' : 'default' });
  };

  const runMigrationAction = async (action: 'validate' | 'approve' | 'promote', batchId: string) => {
    setMigrationBusy(`${action}:${batchId}`);
    try {
      const rpc = action === 'validate' ? 'validate_legacy_migration_batch' : action === 'approve' ? 'approve_legacy_migration_batch' : 'promote_legacy_migration_batch';
      const { error } = await supabase.rpc(rpc as never, { _batch_id: batchId } as never);
      if (error) throw error;
      toast({ title: action === 'validate' ? 'Batch validated' : action === 'approve' ? 'Batch approved' : 'Batch promoted', description: 'The governed migration state was advanced successfully.' });
      await refreshBatches();
      await loadRows(batchId);
    } catch (error) { toast({ title: `Migration ${action} failed`, description: error instanceof Error ? error.message : 'The migration action could not be completed.', variant: 'destructive' }); }
    finally { setMigrationBusy(null); }
  };

  const findCandidates = async (rowId: string) => {
    setMigrationBusy(`match:${rowId}`);
    try {
      const { data, error } = await supabase.rpc('get_legacy_patient_candidates' as never, { _row_id: rowId } as never);
      if (error) throw error;
      setCandidates((current) => ({ ...current, [rowId]: (data ?? []) as PatientCandidate[] }));
    } catch (error) { toast({ title: 'Patient matching failed', description: error instanceof Error ? error.message : 'Unable to retrieve candidates.', variant: 'destructive' }); }
    finally { setMigrationBusy(null); }
  };

  const reconcile = async (rowId: string, candidate: PatientCandidate) => {
    setMigrationBusy(`reconcile:${rowId}`);
    try {
      const { error } = await supabase.rpc('reconcile_legacy_migration_row' as never, { _row_id: rowId, _patient_id: candidate.patient_id, _match_confidence: candidate.confidence, _match_method: candidate.method } as never);
      if (error) throw error;
      toast({ title: 'Patient reconciled', description: `${candidate.patient_code} selected using ${candidate.method.replaceAll('_', ' ')}.` });
      await loadRows(selectedBatch!);
    } catch (error) { toast({ title: 'Reconciliation failed', description: error instanceof Error ? error.message : 'The patient match could not be saved.', variant: 'destructive' }); }
    finally { setMigrationBusy(null); }
  };

  const downloadTemplate = () => {
    const csv = `${templateHeaders[entity].join(',')}\n${templateHeaders[entity].map((field) => field === 'source_system' ? 'Legacy system' : `${field}_example`).join(',')}`;
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8;' })); const link = document.createElement('a'); link.href = url; link.download = `${entity}-migration-template.csv`; link.click(); URL.revokeObjectURL(url);
  };

  return <div className="space-y-6 animate-fade-in">
    <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Database className="w-6 h-6 text-primary" /> Data Import & Migration Workspace</h1><p className="text-muted-foreground">Controlled master-data loading and legacy-system migration with validation, audit and reconciliation boundaries.</p></div>
    <div className="rounded-xl border border-primary/20 bg-primary/5 p-4 text-sm flex gap-3"><ShieldCheck className="w-5 h-5 text-primary shrink-0" /><div><strong>Migration-safe design.</strong> Reference data can be promoted into native catalogues. Legacy clinical records are staged first so patient matching, provenance and clinical reconciliation can be completed before they become part of the active record.</div></div>
    <div className="card-medical p-5 space-y-4">
      <div className="grid gap-3 md:grid-cols-3"><select value={entity} onChange={(e) => { setEntity(e.target.value as Entity); setRows([]); setErrors([]); setFileName(''); }} className="input-medical"><option value="patients">Patients</option><option value="pharmacy_inventory">Pharmacy inventory</option><option value="icd_codes">ICD-10 codes</option><option value="stg_diagnoses">Ghana STG diagnoses</option><option value="service_tariffs">Services & tariffs</option><option value="legacy_clinical_records">Legacy clinical records</option></select><input value={sourceSystem} onChange={(e) => setSourceSystem(e.target.value)} placeholder="Source system / standard" className="input-medical" /><input value={sourceVersion} onChange={(e) => setSourceVersion(e.target.value)} placeholder="Source version (optional)" className="input-medical" /></div>
      <p className="text-sm text-muted-foreground">{schemas[entity].description}</p>
      <div className="flex flex-wrap gap-2"><button type="button" onClick={downloadTemplate} className="btn-ghost inline-flex items-center gap-2"><FileSpreadsheet className="w-4 h-4" /> Download template</button><input type="file" accept=".csv,.xlsx,.xls" onChange={(e) => { const file = e.target.files?.[0]; if (file) void parse(file); e.currentTarget.value = ''; }} className="input-medical flex-1 min-w-64" /></div>
      {rows.length > 0 && <><p className="text-sm">{fileName} · {rows.length.toLocaleString()} rows</p><div className="overflow-auto border border-border rounded-xl max-h-80"><table className="text-xs w-full"><thead><tr>{Object.keys(rows[0]).map((key) => <th key={key} className="text-left p-2 border-b border-border">{key}</th>)}</tr></thead><tbody>{rows.slice(0, PREVIEW_ROWS).map((row, i) => <tr key={i} className="border-b border-border">{Object.keys(rows[0]).map((key) => <td key={key} className="p-2 max-w-48 truncate">{String(row[key] ?? '')}</td>)}</tr>)}</tbody></table></div><button disabled={busy} onClick={() => void importRows()} className="btn-primary inline-flex items-center gap-2"><Upload className="w-4 h-4" />{busy ? 'Processing…' : `Process ${rows.length.toLocaleString()} rows`}</button></>}
    </div>

    <div className="card-medical p-5 space-y-4">
      <div className="flex items-center justify-between gap-3"><div><h2 className="font-semibold flex items-center gap-2"><ShieldCheck className="w-5 h-5 text-primary" /> Legacy reconciliation & approval</h2><p className="text-xs text-muted-foreground">Import → Match → Reconcile → Validate → Approve → Promote to the legacy continuity layer.</p></div><button type="button" onClick={() => void refreshBatches()} className="btn-ghost inline-flex items-center gap-2"><RefreshCw className="w-4 h-4" /> Refresh</button></div>
      {batches.length === 0 ? <p className="text-sm text-muted-foreground">No legacy migration batches have been staged.</p> : <div className="space-y-2">{batches.map((batch) => <div key={batch.id} className={`border rounded-xl p-3 ${selectedBatch === batch.id ? 'border-primary bg-primary/5' : 'border-border'}`}><div className="flex flex-col lg:flex-row lg:items-center justify-between gap-3"><div className="min-w-0"><p className="font-medium truncate">{batch.file_name || batch.source_system}</p><p className="text-xs text-muted-foreground">{batch.total_rows} rows · staged {batch.staged_rows} · accepted {batch.accepted_rows} · rejected {batch.rejected_rows} · {new Date(batch.created_at).toLocaleString()}</p></div><div className="flex flex-wrap gap-2"><span className="text-xs rounded-full border px-2 py-1">{batch.status}</span><button type="button" onClick={() => void loadRows(batch.id)} className="btn-ghost text-xs">Review rows</button>{batch.status === 'staged' && <button type="button" disabled={migrationBusy === `validate:${batch.id}`} onClick={() => void runMigrationAction('validate', batch.id)} className="btn-secondary text-xs">Validate</button>}{batch.status === 'ready' && <button type="button" disabled={migrationBusy === `approve:${batch.id}`} onClick={() => void runMigrationAction('approve', batch.id)} className="btn-secondary text-xs">Approve</button>}{batch.status === 'importing' && <button type="button" disabled={migrationBusy === `promote:${batch.id}`} onClick={() => void runMigrationAction('promote', batch.id)} className="btn-primary text-xs">Promote</button>}</div></div></div>)}</div>}

      {selectedBatch && <div className="border-t border-border pt-4 space-y-3"><div className="flex items-center gap-2 text-sm font-medium"><UserCheck className="w-4 h-4 text-primary" /> Patient reconciliation</div>{migrationRows.length === 0 ? <p className="text-xs text-muted-foreground">No rows found for this batch.</p> : <div className="space-y-3">{migrationRows.map((row) => <div key={row.id} className="border border-border rounded-xl p-3 space-y-2"><div className="flex flex-col md:flex-row md:items-center justify-between gap-2"><div className="text-xs"><span className="font-medium">Row {row.source_row_number}</span> · {String(row.raw_data.record_type ?? 'record')} · {String(row.raw_data.source_patient_key ?? row.source_key ?? 'no patient key')} · <span className="font-medium">{row.row_status}</span>{row.match_confidence !== null && ` · ${(row.match_confidence * 100).toFixed(1)}%`}</div><button type="button" disabled={migrationBusy === `match:${row.id}`} onClick={() => void findCandidates(row.id)} className="btn-ghost text-xs inline-flex items-center gap-1"><Search className="w-3 h-3" /> Find patient</button></div>{row.validation_errors?.length > 0 && <p className="text-xs text-critical">{row.validation_errors.join(' · ')}</p>}{candidates[row.id]?.map((candidate) => <div key={candidate.patient_id} className="flex flex-col md:flex-row md:items-center justify-between gap-2 rounded-lg bg-muted/40 p-2 text-xs"><div><strong>{candidate.patient_code}</strong> — {candidate.first_name} {candidate.last_name} {candidate.date_of_birth ? `· ${candidate.date_of_birth}` : ''}<span className="ml-2 text-muted-foreground">{candidate.method.replaceAll('_', ' ')} · {(candidate.confidence * 100).toFixed(1)}%</span></div><button type="button" disabled={migrationBusy === `reconcile:${row.id}`} onClick={() => void reconcile(row.id, candidate)} className="btn-secondary text-xs inline-flex items-center gap-1"><CheckCircle2 className="w-3 h-3" /> Select</button></div>)}</div>)}</div>}</div>}
    </div>

    {entity === 'legacy_clinical_records' && <div className="rounded-xl border border-warning/30 bg-warning/5 p-4 text-sm"><strong>Continuity-of-care workflow:</strong> legacy records are staged with source provenance. They must be matched, chronologically validated and approved before promotion. Promotion writes only to the canonical legacy continuity layer; native encounters, diagnoses, prescriptions and laboratory results are not automatically created.</div>}
    {errors.length > 0 && <div className="card-medical p-5"><h2 className="font-semibold text-critical mb-2">Import validation issues</h2><ul className="text-xs list-disc pl-5 space-y-1">{errors.slice(0, 50).map((error, i) => <li key={i}>{error}</li>)}</ul></div>}
  </div>;
}
