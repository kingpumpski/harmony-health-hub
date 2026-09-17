import { useState } from 'react';
import Papa from 'papaparse';
import { Database, FileSpreadsheet, Upload, AlertTriangle, ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

type Entity = 'patients' | 'pharmacy_inventory' | 'icd_codes' | 'stg_diagnoses' | 'service_tariffs' | 'legacy_clinical_records';
type Row = Record<string, string | number | boolean | null>;
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
      } else {
        for (const row of validRows) {
          if (entity === 'patients') await supabase.from('patients').insert({ ...row, created_by: user.id } as never).throwOnError();
          if (entity === 'pharmacy_inventory') await supabase.from('pharmacy_inventory').insert({ drug_name: String(row.drug_name), generic_name: row.generic_name, strength: row.strength, form: row.form, stock_quantity: Number(row.stock_quantity ?? 0), reorder_level: Number(row.reorder_level ?? 20), unit_price: Number(row.unit_price ?? 0), supplier: row.supplier, expiry_date: row.expiry_date } as never).throwOnError();
          if (entity === 'icd_codes') await supabase.from('icd_codes').insert({ code: String(row.code), description: String(row.description), version: row.version ?? 'ICD-10', category: row.category } as never).throwOnError();
          inserted++;
        }
      }
      const sourceFormat = fileName.toLowerCase().endsWith('.csv') ? 'csv' : 'xlsx';
      await supabase.from('bulk_import_jobs').insert({ entity_type: entity === 'legacy_clinical_records' ? 'patients' : entity, source_format: sourceFormat, file_name: fileName || null, total_rows: rows.length, successful_rows: inserted, failed_rows: failed.length, errors: failed.map((reason) => ({ reason })), status: failed.length === rows.length ? 'failed' : failed.length ? 'completed_with_errors' : 'completed', created_by: user.id, completed_at: new Date().toISOString() } as never);
    } catch (error) { failed.push(error instanceof Error ? error.message : 'Import failed'); }
    setErrors(failed); setBusy(false); setRows([]); setFileName('');
    toast({ title: failed.length ? 'Import completed with issues' : 'Import complete', description: `${inserted}/${rows.length} rows processed${failed.length ? `; ${failed.length} issues recorded` : ''}.`, variant: failed.length && inserted === 0 ? 'destructive' : 'default' });
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
    {entity === 'legacy_clinical_records' && <div className="rounded-xl border border-warning/30 bg-warning/5 p-4 text-sm"><strong>Continuity-of-care workflow:</strong> legacy records are staged with source provenance. They should be matched to existing patients and clinically reviewed before promotion into encounters, diagnoses, prescriptions, laboratory results or other native modules.</div>}
    {errors.length > 0 && <div className="card-medical p-5"><h2 className="font-semibold text-critical mb-2">Import validation issues</h2><ul className="text-xs list-disc pl-5 space-y-1">{errors.slice(0, 50).map((error, i) => <li key={i}>{error}</li>)}</ul></div>}
  </div>;
}
