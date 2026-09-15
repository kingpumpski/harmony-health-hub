import { useEffect, useMemo, useState } from 'react';
import Papa from 'papaparse';
import * as XLSX from 'xlsx';
import { Database, FileSpreadsheet, Upload, AlertTriangle, ShieldCheck, CheckCircle2, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

type Entity = 'patients' | 'pharmacy_inventory' | 'icd_codes' | 'stg_ghana' | 'diagnosis_workbook';
interface Row { [key: string]: string | number | null }
interface SheetAssessment { name: string; rows: number; columns: string[]; missingHeaders: string[]; duplicateRows: number; preview: Row[] }
interface DiagnosisImportCounts { batch_id: string; status: string; total_rows: number; accepted_rows: number; rejected_rows: number; duplicate_rows: number; unmapped_rows: number }
const schemas: Record<Exclude<Entity, 'diagnosis_workbook' | 'stg_ghana'>, { required: string[]; fields: string[] }> = {
  patients: { required: ['first_name', 'last_name'], fields: ['first_name','last_name','date_of_birth','gender','phone','email','address','city','ghana_card_number','blood_group','genotype','allergies','chronic_conditions','insurance_provider','insurance_number','emergency_contact_name','emergency_contact_phone'] },
  pharmacy_inventory: { required: ['drug_name'], fields: ['drug_name','generic_name','strength','form','stock_quantity','reorder_level','unit_price','supplier','expiry_date'] },
  icd_codes: { required: ['code','description'], fields: ['code','description','version','category'] },
};
const normalize = (value: unknown): string | number | null => value === undefined || value === null || String(value).trim() === '' ? null : typeof value === 'number' ? value : String(value).trim();
const normalizeRows = (data: Record<string, unknown>[]) => data.map(row => Object.fromEntries(Object.entries(row).map(([k,v]) => [String(k).trim().toLowerCase(), normalize(v)]))) as Row[];
const compactKey = (value: unknown) => String(value ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
const firstValue = (row: Row, aliases: string[]) => {
  for (const alias of aliases) {
    const value = row[alias];
    if (value !== null && value !== undefined && String(value).trim() !== '') return String(value).trim();
  }
  return '';
};
const parseSynonyms = (value: string) => value.split(/[|;,]/).map(item => item.trim()).filter(Boolean);

export default function DataImport() {
  const { user } = useAuth();
  const [entity, setEntity] = useState<Entity>('patients');
  const [rows, setRows] = useState<Row[]>([]);
  const [fileName, setFileName] = useState('');
  const [busy, setBusy] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [assessment, setAssessment] = useState<SheetAssessment[]>([]);
  const [ghanaStgStandardId, setGhanaStgStandardId] = useState<string | null>(null);
  const [stgDatasetRows, setStgDatasetRows] = useState<number | null>(null);
  const [diagnosisBatchId, setDiagnosisBatchId] = useState<string | null>(null);
  const [diagnosisCounts, setDiagnosisCounts] = useState<DiagnosisImportCounts | null>(null);

  const diagnosisReady = useMemo(() => diagnosisCounts?.status === 'validated' && diagnosisCounts.rejected_rows === 0 && diagnosisCounts.duplicate_rows === 0 && diagnosisCounts.unmapped_rows === 0, [diagnosisCounts]);

  useEffect(() => {
    let cancelled = false;
    const loadGhanaStg = async () => {
      const { data, error } = await supabase.from('diagnosis_standards').select('id').eq('code', 'GH-STG').maybeSingle();
      if (cancelled) return;
      if (error) { console.warn('Unable to load Ghana STG standard', error); return; }
      setGhanaStgStandardId(data?.id ?? null);
      if (data?.id) {
        const { count } = await supabase.from('stg_diagnoses').select('id', { count: 'exact', head: true }).eq('standard_id', data.id);
        if (!cancelled) setStgDatasetRows(count ?? 0);
      }
    };
    void loadGhanaStg();
    return () => { cancelled = true; };
  }, []);

  if (user?.role !== 'admin') return <div className="p-8 text-center"><AlertTriangle className="w-10 h-10 text-warning mx-auto mb-2" /><h2 className="font-semibold text-xl">Admin only</h2><p className="text-muted-foreground">Bulk database import requires administrator access.</p></div>;

  const validate = (row: Row, index: number) => {
    for (const field of schemas[entity as Exclude<Entity, 'diagnosis_workbook' | 'stg_ghana'>].required) if (!row[field]) return `Row ${index + 2}: missing ${field}`;
    if (entity === 'patients' && row.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(row.email))) return `Row ${index + 2}: invalid email`;
    return null;
  };

  const stageDiagnosisWorkbook = async (workbook: XLSX.WorkBook, file: File) => {
    if (!ghanaStgStandardId || !user?.id) throw new Error('Ghana STG standard or authenticated administrator is unavailable.');
    const sheets: SheetAssessment[] = [];
    const stagedRows: Array<Record<string, unknown>> = [];
    for (const name of workbook.SheetNames) {
      const sheet = workbook.Sheets[name];
      const raw = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, { defval: null });
      const data = normalizeRows(raw);
      const columns = data.length ? Object.keys(data[0]) : (XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, defval: null })[0] || []).map(String).map(v => v.trim().toLowerCase()).filter(Boolean);
      const seen = new Set<string>(); let duplicateRows = 0;
      for (const row of data) { const key = JSON.stringify(row); if (seen.has(key)) duplicateRows++; else seen.add(key); }
      const missingHeaders = columns.length === 0 ? ['no header row detected'] : [];
      sheets.push({ name, rows: data.length, columns, missingHeaders, duplicateRows, preview: data.slice(0, 5) });
      data.forEach((row, index) => {
        const displayName = firstValue(row, ['diagnosis','diagnosis name','name','condition','condition name','display name','term','description']);
        const sourceCode = firstValue(row, ['code','diagnosis code','stg code','stg-code','source code','diagnosis id','id']);
        const description = firstValue(row, ['clinical description','description','details','definition','clinical details']);
        const category = firstValue(row, ['category','chapter','section','system','body system','classification']);
        const synonymText = firstValue(row, ['synonyms','synonym','aliases','alternative names','alternative name']);
        const icd10Code = firstValue(row, ['icd-10','icd10','icd-10 code','icd10 code','icd code','icd code(s)','icd']);
        stagedRows.push({ batch_id: '__BATCH__', sheet_name: name, source_row_number: index + 2, source_code: sourceCode || null, display_name: displayName || null, description: description || null, category: category || null, synonyms: parseSynonyms(synonymText), icd10_code: icd10Code || null, normalized_key: compactKey(displayName), row_status: 'pending' });
      });
    }
    const totalRows = stagedRows.length;
    const duplicateRows = sheets.reduce((sum, sheet) => sum + sheet.duplicateRows, 0);
    const validationErrors = sheets.flatMap(sheet => sheet.missingHeaders.map(reason => ({ sheet: sheet.name, reason })));
    const { data: batch, error: batchError } = await supabase.from('diagnosis_import_batches').insert({ standard_id: ghanaStgStandardId, file_name: file.name, source_format: file.name.toLowerCase().endsWith('.xls') ? 'xls' : 'xlsx', assessment_only: true, status: 'assessed', total_sheets: sheets.length, total_rows: totalRows, duplicate_rows: duplicateRows, validation_errors: validationErrors, sheet_assessments: sheets.map(({ preview, ...summary }) => summary), created_by: user.id } as never).select('id').single();
    if (batchError || !batch) throw new Error(batchError?.message || 'Unable to create diagnosis import batch.');
    const batchId = String((batch as { id: string }).id);
    for (let offset = 0; offset < stagedRows.length; offset += 500) {
      const chunk = stagedRows.slice(offset, offset + 500).map(row => ({ ...row, batch_id: batchId }));
      const { error } = await supabase.from('diagnosis_import_rows').insert(chunk as never);
      if (error) throw new Error(`Unable to stage workbook rows ${offset + 1}-${Math.min(offset + 500, stagedRows.length)}: ${error.message}`);
    }
    setAssessment(sheets); setDiagnosisBatchId(batchId); setDiagnosisCounts({ batch_id: batchId, status: 'assessed', total_rows: totalRows, accepted_rows: 0, rejected_rows: 0, duplicate_rows: 0, unmapped_rows: 0 });
    toast({ title: 'STG-Ghana workbook staged', description: `${sheets.length} worksheet${sheets.length === 1 ? '' : 's'} and ${totalRows} rows are staged for governed validation. No clinical diagnosis records were changed.` });
  };

  const assessWorkbook = (file: File) => {
    setFileName(file.name); setRows([]); setErrors([]); setAssessment([]); setDiagnosisBatchId(null); setDiagnosisCounts(null);
    if (!ghanaStgStandardId) { toast({ title: 'Ghana STG standard unavailable', description: 'The GH-STG diagnosis standard is not configured in the database.', variant: 'destructive' }); return; }
    if (!/\.(xlsx|xls)$/i.test(file.name)) { toast({ title: 'Diagnosis assessment requires Excel', description: 'Select an .xlsx or .xls workbook.', variant: 'destructive' }); return; }
    const reader = new FileReader(); reader.onload = async e => { try { const workbook = XLSX.read(e.target?.result, { type: 'array', cellDates: true }); await stageDiagnosisWorkbook(workbook, file); } catch (error) { toast({ title: 'Workbook staging failed', description: error instanceof Error ? error.message : 'Invalid workbook.', variant: 'destructive' }); } };
    reader.readAsArrayBuffer(file);
  };

  const parse = (file: File) => {
    setFileName(file.name); setErrors([]); setAssessment([]);
    if (file.name.toLowerCase().endsWith('.csv')) { Papa.parse<Row>(file, { header: true, skipEmptyLines: true, transformHeader: h => h.trim().toLowerCase(), complete: result => setRows(result.data.map(r => Object.fromEntries(Object.entries(r).map(([k,v]) => [k, normalize(v)]))) as Row[]), error: e => toast({ title: 'CSV parse failed', description: e.message, variant: 'destructive' }) }); return; }
    const reader = new FileReader(); reader.onload = e => { try { const workbook = XLSX.read(e.target?.result, { type: 'array' }); const sheet = workbook.Sheets[workbook.SheetNames[0]]; setRows(normalizeRows(XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, { defval: null }))); } catch (error) { toast({ title: 'Spreadsheet parse failed', description: error instanceof Error ? error.message : 'Invalid workbook.', variant: 'destructive' }); } }; reader.readAsArrayBuffer(file);
  };

  const refreshDiagnosisBatch = async (batchId = diagnosisBatchId) => {
    if (!batchId) return;
    const { data, error } = await supabase.from('diagnosis_import_batches').select('id,status,total_rows,accepted_rows,rejected_rows,duplicate_rows,unmapped_rows').eq('id', batchId).maybeSingle();
    if (error || !data) { toast({ title: 'Unable to refresh batch', description: error?.message || 'Batch not found.', variant: 'destructive' }); return; }
    setDiagnosisCounts(data as DiagnosisImportCounts);
  };

  const runDiagnosisAction = async (action: 'validate' | 'approve' | 'import') => {
    if (!diagnosisBatchId) return;
    setBusy(true);
    try {
      const rpcName = action === 'validate' ? 'validate_diagnosis_import_batch' : action === 'approve' ? 'approve_diagnosis_import_batch' : 'import_approved_diagnosis_batch';
      const { data, error } = await supabase.rpc(rpcName as never, { p_batch_id: diagnosisBatchId } as never);
      if (error) throw new Error(error.message);
      const result = (data ?? {}) as Record<string, unknown>;
      if (action === 'validate') {
        setDiagnosisCounts({ batch_id: diagnosisBatchId, status: String(result.status ?? 'validated'), total_rows: Number(result.total_rows ?? 0), accepted_rows: Number(result.accepted_rows ?? 0), rejected_rows: Number(result.rejected_rows ?? 0), duplicate_rows: Number(result.duplicate_rows ?? 0), unmapped_rows: Number(result.unmapped_rows ?? 0) });
      } else await refreshDiagnosisBatch();
      if (action === 'import') {
        const inserted = Number(result.inserted_rows ?? 0);
        setStgDatasetRows(previous => (previous ?? 0) + inserted);
        toast({ title: 'STG-Ghana import completed', description: `${inserted} approved diagnosis records were added to the Ghana STG catalogue.` });
      } else toast({ title: action === 'approve' ? 'Batch approved' : 'Batch validated', description: action === 'approve' ? 'The workbook is now authorized for controlled import.' : 'Validation counts have been reconciled against the staged rows.' });
    } catch (error) { toast({ title: `Diagnosis ${action} failed`, description: error instanceof Error ? error.message : 'Operation failed.', variant: 'destructive' }); await refreshDiagnosisBatch(); }
    finally { setBusy(false); }
  };

  const importRows = async () => {
    if (!rows.length || !user?.id || entity === 'diagnosis_workbook' || entity === 'stg_ghana') return; setBusy(true); const failed: string[] = []; let inserted = 0;
    for (let i = 0; i < rows.length; i++) { const row = rows[i]; const validation = validate(row, i); if (validation) { failed.push(validation); continue; } try {
      if (entity === 'patients') await supabase.from('patients').insert({ ...row, created_by: user.id } as never).throwOnError();
      if (entity === 'pharmacy_inventory') await supabase.from('pharmacy_inventory').insert({ drug_name: String(row.drug_name), generic_name: row.generic_name, strength: row.strength, form: row.form, stock_quantity: Number(row.stock_quantity ?? 0), reorder_level: Number(row.reorder_level ?? 20), unit_price: Number(row.unit_price ?? 0), supplier: row.supplier, expiry_date: row.expiry_date } as never).throwOnError();
      if (entity === 'icd_codes') await supabase.from('icd_codes').insert({ code: String(row.code), description: String(row.description), version: row.version ?? 'ICD-10', category: row.category } as never).throwOnError();
      inserted++;
    } catch (error) { failed.push(`Row ${i + 2}: ${error instanceof Error ? error.message : 'Insert failed'}`); } }
    const sourceFormat = fileName.toLowerCase().endsWith('.csv') ? 'csv' : 'xlsx'; const jobStatus = failed.length === rows.length ? 'failed' : failed.length > 0 ? 'completed_with_errors' : 'completed';
    const { error: auditError } = await supabase.from('bulk_import_jobs').insert({ entity, filename: fileName || null, total_rows: rows.length, inserted_rows: inserted, failed_rows: failed.length, errors: failed.map(reason => ({ reason })), status: jobStatus, created_by: user.id } as never);
    if (auditError) toast({ title: 'Import audit warning', description: auditError.message }); setErrors(failed); setBusy(false); setRows([]); setFileName(''); toast({ title: 'Import complete', description: `${inserted}/${rows.length} rows inserted${failed.length ? `; ${failed.length} failed` : ''}.`, variant: failed.length === rows.length ? 'destructive' : 'default' });
  };

  const handleFileSelection = (fileList: FileList | null) => {
    const file = fileList?.[0];
    if (!file) return;

    if (entity === 'stg_ghana' || entity === 'diagnosis_workbook') {
      assessWorkbook(file);
      return;
    }

    parse(file);
  };

  return <div className="space-y-6 animate-fade-in">
    <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Database className="w-6 h-6 text-primary" /> XLSX / CSV Data Import</h1><p className="text-muted-foreground">Controlled bulk import for approved administrative and clinical reference data sets.</p></div>
    <div className="rounded-xl border border-warning/20 bg-warning/5 p-3 text-sm text-muted-foreground">Review the preview before importing. STG-Ghana is a controlled clinical reference dataset: upload, stage, validate and approve the Ghana STG workbook before clinicians can use its diagnoses.</div>
    <div className="card-medical p-5 space-y-4">
      <select value={entity} onChange={e => { setEntity(e.target.value as Entity); setRows([]); setErrors([]); setAssessment([]); setDiagnosisBatchId(null); setDiagnosisCounts(null); }} className="input-medical w-full">
        <option value="patients">Patients</option><option value="pharmacy_inventory">Pharmacy inventory</option><option value="icd_codes">ICD-10 codes</option><option value="stg_ghana">STG-Ghana — diagnosis dataset (required)</option><option value="diagnosis_workbook">Diagnosis workbook — assess and stage only</option>
      </select>
      {entity === 'stg_ghana' && <div className="rounded-lg border border-border bg-muted/20 p-3 text-sm"><div className="font-medium">Ghana Standard Treatment Guidelines</div><div className="text-xs text-muted-foreground mt-1">Dataset target: GH-STG · 7th Edition (2017). Current loaded diagnosis records: {stgDatasetRows ?? 'checking…'}.</div>{stgDatasetRows === 0 && <div className="text-xs text-warning mt-1">No STG-Ghana diagnosis dataset is loaded yet. Select the approved Excel workbook to stage and validate it; staging does not change the clinical catalogue.</div>}</div>}
      <input type="file" accept={entity === 'stg_ghana' || entity === 'diagnosis_workbook' ? '.xlsx,.xls' : '.csv,.xlsx,.xls'} onChange={e => handleFileSelection(e.target.files)} className="input-medical w-full" />
      {(entity === 'stg_ghana' || entity === 'diagnosis_workbook') && assessment.length > 0 && <div className="space-y-3"><div className="flex items-center gap-2 text-sm font-medium"><ShieldCheck className="w-4 h-4" />Workbook assessment and governed staging</div>{assessment.map(sheet => <div key={sheet.name} className="border border-border rounded-xl p-3"><div className="flex justify-between gap-3"><strong>{sheet.name}</strong><span className="text-xs text-muted-foreground">{sheet.rows} rows · {sheet.columns.length} columns · {sheet.duplicateRows} duplicate rows</span></div><p className="text-xs text-muted-foreground mt-1">Columns: {sheet.columns.join(', ') || 'none detected'}</p>{sheet.missingHeaders.length > 0 && <p className="text-xs text-critical mt-1">{sheet.missingHeaders.join(', ')}</p>}{sheet.preview.length > 0 && <div className="overflow-auto mt-2"><table className="text-xs w-full"><thead><tr>{sheet.columns.map(k => <th key={k} className="text-left p-1 border-b border-border">{k}</th>)}</tr></thead><tbody>{sheet.preview.map((row,i) => <tr key={i}>{sheet.columns.map(k => <td key={k} className="p-1 max-w-48 truncate">{String(row[k] ?? '')}</td>)}</tr>)}</tbody></table></div>}</div>)}</div>}
      {diagnosisCounts && diagnosisBatchId && (entity === 'stg_ghana' || entity === 'diagnosis_workbook') && <div className="rounded-xl border border-border p-4 space-y-3"><div className="flex items-center justify-between gap-3"><div><div className="font-medium">Governed import batch</div><div className="text-xs text-muted-foreground">Status: {diagnosisCounts.status} · Batch {diagnosisBatchId.slice(0, 8)}…</div></div><button type="button" disabled={busy} onClick={() => void refreshDiagnosisBatch()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="w-4 h-4" />Refresh</button></div><div className="grid grid-cols-2 md:grid-cols-5 gap-2 text-xs"><div className="rounded-lg bg-muted/30 p-2">Total<strong className="block text-lg">{diagnosisCounts.total_rows}</strong></div><div className="rounded-lg bg-muted/30 p-2">Accepted<strong className="block text-lg">{diagnosisCounts.accepted_rows}</strong></div><div className="rounded-lg bg-muted/30 p-2">Rejected<strong className="block text-lg">{diagnosisCounts.rejected_rows}</strong></div><div className="rounded-lg bg-muted/30 p-2">Duplicates<strong className="block text-lg">{diagnosisCounts.duplicate_rows}</strong></div><div className="rounded-lg bg-muted/30 p-2">Unmapped<strong className="block text-lg">{diagnosisCounts.unmapped_rows}</strong></div></div><div className="flex flex-wrap gap-2"><button type="button" disabled={busy || diagnosisCounts.status === 'completed'} onClick={() => void runDiagnosisAction('validate')} className="btn-secondary inline-flex items-center gap-2"><ShieldCheck className="w-4 h-4" />{busy ? 'Working…' : 'Validate batch'}</button><button type="button" disabled={busy || !diagnosisReady || diagnosisCounts.status !== 'validated'} onClick={() => void runDiagnosisAction('approve')} className="btn-primary inline-flex items-center gap-2"><CheckCircle2 className="w-4 h-4" />Approve batch</button><button type="button" disabled={busy || diagnosisCounts.status !== 'approved'} onClick={() => void runDiagnosisAction('import')} className="btn-primary inline-flex items-center gap-2"><Upload className="w-4 h-4" />Import approved batch</button></div>{diagnosisCounts.status === 'validated' && !diagnosisReady && <p className="text-xs text-warning">Approval is blocked until rejected, duplicate and unmapped counts are all zero. Correct the source workbook and stage a new batch rather than bypassing validation.</p>}{diagnosisCounts.status === 'completed' && <p className="text-xs text-success flex items-center gap-1"><CheckCircle2 className="w-4 h-4" />Import completed. The STG-Ghana catalogue can now be searched by clinicians.</p>}</div>}
      {rows.length > 0 && <><p className="text-sm flex items-center gap-2"><FileSpreadsheet className="w-4 h-4" />{fileName} · {rows.length} rows</p><div className="overflow-auto border border-border rounded-xl max-h-80"><table className="text-xs w-full"><thead><tr>{Object.keys(rows[0]).map(k => <th key={k} className="text-left p-2 border-b border-border">{k}</th>)}</tr></thead><tbody>{rows.slice(0,10).map((row,i) => <tr key={i} className="border-b border-border">{Object.keys(rows[0]).map(k => <td key={k} className="p-2 max-w-48 truncate">{String(row[k] ?? '')}</td>)}</tr>)}</tbody></table></div><button disabled={busy} onClick={() => void importRows()} className="btn-primary inline-flex items-center gap-2"><Upload className="w-4 h-4" />{busy ? 'Importing…' : `Import ${rows.length} rows`}</button></>}
    </div>
    {errors.length > 0 && <div className="card-medical p-5"><h2 className="font-semibold text-critical mb-2">Import errors</h2><ul className="text-xs list-disc pl-5 space-y-1">{errors.slice(0,50).map((e,i) => <li key={i}>{e}</li>)}</ul></div>}
  </div>;
}
