import { useState } from 'react';
import Papa from 'papaparse';
import { Database, FileSpreadsheet, Upload, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

type Entity = 'patients' | 'pharmacy_inventory' | 'icd_codes';
type Row = Record<string, string | number | null>;

const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_ROWS = 10_000;
const PREVIEW_ROWS = 10;

const schemas: Record<Entity, { required: string[] }> = {
  patients: { required: ['first_name', 'last_name'] },
  pharmacy_inventory: { required: ['drug_name'] },
  icd_codes: { required: ['code', 'description'] },
};

const normalize = (value: unknown): string | number | null => {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  return typeof value === 'number' ? value : String(value).trim();
};

const normalizeRows = (data: Array<Record<string, unknown>>): Row[] =>
  data.map((row) =>
    Object.fromEntries(
      Object.entries(row).map(([key, value]) => [key.trim().toLowerCase(), normalize(value)]),
    ),
  );

export default function DataImport() {
  const { user } = useAuth();
  const [entity, setEntity] = useState<Entity>('patients');
  const [rows, setRows] = useState<Row[]>([]);
  const [fileName, setFileName] = useState('');
  const [busy, setBusy] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);

  if (user?.role !== 'admin') {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="w-10 h-10 text-warning mx-auto mb-2" />
        <h2 className="font-semibold text-xl">Admin only</h2>
        <p className="text-muted-foreground">Bulk database import requires administrator access.</p>
      </div>
    );
  }

  const parse = async (file: File) => {
    setFileName('');
    setRows([]);
    setErrors([]);

    if (file.size > MAX_FILE_BYTES) {
      toast({
        title: 'File too large',
        description: `Imports are limited to ${MAX_FILE_BYTES / 1024 / 1024} MB.`,
        variant: 'destructive',
      });
      return;
    }

    const lowerName = file.name.toLowerCase();
    if (!lowerName.endsWith('.csv') && !lowerName.endsWith('.xlsx') && !lowerName.endsWith('.xls')) {
      toast({ title: 'Unsupported file', description: 'Choose a CSV, XLSX, or XLS file.', variant: 'destructive' });
      return;
    }

    setFileName(file.name);

    if (lowerName.endsWith('.csv')) {
      Papa.parse<Record<string, unknown>>(file, {
        header: true,
        skipEmptyLines: true,
        transformHeader: (header) => header.trim().toLowerCase(),
        complete: (result) => {
          if (result.errors.length) {
            toast({ title: 'CSV parse failed', description: result.errors[0].message, variant: 'destructive' });
            setFileName('');
            return;
          }
          if (result.data.length > MAX_ROWS) {
            toast({ title: 'Too many rows', description: `Imports are limited to ${MAX_ROWS.toLocaleString()} rows.`, variant: 'destructive' });
            setFileName('');
            return;
          }
          setRows(normalizeRows(result.data));
        },
        error: (error) => {
          setFileName('');
          toast({ title: 'CSV parse failed', description: error.message, variant: 'destructive' });
        },
      });
      return;
    }

    try {
      const XLSX = await import('xlsx');
      const buffer = await file.arrayBuffer();
      const workbook = XLSX.read(buffer, { type: 'array', dense: true, cellFormula: false });
      const firstSheetName = workbook.SheetNames[0];
      if (!firstSheetName) throw new Error('The workbook contains no worksheets.');
      const sheet = workbook.Sheets[firstSheetName];
      const data = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, { defval: null, raw: true });
      if (data.length > MAX_ROWS) throw new Error(`Imports are limited to ${MAX_ROWS.toLocaleString()} rows.`);
      setRows(normalizeRows(data));
    } catch (error) {
      setFileName('');
      toast({ title: 'Spreadsheet parse failed', description: error instanceof Error ? error.message : 'Invalid workbook.', variant: 'destructive' });
    }
  };

  const validate = (row: Row, index: number) => {
    for (const field of schemas[entity].required) {
      if (!row[field]) return `Row ${index + 2}: missing ${field}`;
    }
    if (entity === 'patients' && row.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(row.email))) {
      return `Row ${index + 2}: invalid email`;
    }
    return null;
  };

  const importRows = async () => {
    if (!rows.length || !user?.id || busy) return;
    setBusy(true);
    const failed: string[] = [];
    let inserted = 0;

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const validation = validate(row, i);
      if (validation) {
        failed.push(validation);
        continue;
      }
      try {
        if (entity === 'patients') await supabase.from('patients').insert({ ...row, created_by: user.id } as never).throwOnError();
        if (entity === 'pharmacy_inventory') await supabase.from('pharmacy_inventory').insert({ drug_name: String(row.drug_name), generic_name: row.generic_name, strength: row.strength, form: row.form, stock_quantity: Number(row.stock_quantity ?? 0), reorder_level: Number(row.reorder_level ?? 20), unit_price: Number(row.unit_price ?? 0), supplier: row.supplier, expiry_date: row.expiry_date } as never).throwOnError();
        if (entity === 'icd_codes') await supabase.from('icd_codes').insert({ code: String(row.code), description: String(row.description), version: row.version ?? 'ICD-10', category: row.category } as never).throwOnError();
        inserted++;
      } catch (error) {
        failed.push(`Row ${i + 2}: ${error instanceof Error ? error.message : 'Insert failed'}`);
      }
    }

    const sourceFormat = fileName.toLowerCase().endsWith('.csv') ? 'csv' : 'xlsx';
    const jobStatus = failed.length === rows.length ? 'failed' : failed.length > 0 ? 'completed_with_errors' : 'completed';
    const { error: auditError } = await supabase.from('bulk_import_jobs').insert({ entity_type: entity, source_format: sourceFormat, file_name: fileName || null, total_rows: rows.length, successful_rows: inserted, failed_rows: failed.length, errors: failed.map((reason) => ({ reason })), status: jobStatus, created_by: user.id, completed_at: new Date().toISOString() } as never);
    if (auditError) toast({ title: 'Import audit warning', description: auditError.message });

    setErrors(failed);
    setBusy(false);
    setRows([]);
    setFileName('');
    toast({ title: 'Import complete', description: `${inserted}/${rows.length} rows inserted${failed.length ? `; ${failed.length} failed` : ''}.`, variant: failed.length === rows.length ? 'destructive' : 'default' });
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Database className="w-6 h-6 text-primary" /> XLSX / CSV Data Import</h1>
        <p className="text-muted-foreground">Controlled bulk import for approved administrative data sets.</p>
      </div>
      <div className="rounded-xl border border-warning/20 bg-warning/5 p-3 text-sm text-muted-foreground">Review the preview before importing. Uploads are limited to 10 MB and 10,000 rows and are audited as bulk import jobs.</div>
      <div className="card-medical p-5 space-y-4">
        <select value={entity} onChange={(e) => { setEntity(e.target.value as Entity); setRows([]); setErrors([]); setFileName(''); }} className="input-medical w-full">
          <option value="patients">Patients</option><option value="pharmacy_inventory">Pharmacy inventory</option><option value="icd_codes">ICD-10 codes</option>
        </select>
        <input type="file" accept=".csv,.xlsx,.xls" onChange={(e) => { const file = e.target.files?.[0]; if (file) void parse(file); e.currentTarget.value = ''; }} className="input-medical w-full" />
        {rows.length > 0 && <>
          <p className="text-sm flex items-center gap-2"><FileSpreadsheet className="w-4 h-4" />{fileName} · {rows.length.toLocaleString()} rows</p>
          <div className="overflow-auto border border-border rounded-xl max-h-80"><table className="text-xs w-full"><thead><tr>{Object.keys(rows[0]).map((key) => <th key={key} className="text-left p-2 border-b border-border">{key}</th>)}</tr></thead><tbody>{rows.slice(0, PREVIEW_ROWS).map((row, i) => <tr key={i} className="border-b border-border">{Object.keys(rows[0]).map((key) => <td key={key} className="p-2 max-w-48 truncate">{String(row[key] ?? '')}</td>)}</tr>)}</tbody></table></div>
          <p className="text-xs text-muted-foreground">Previewing the first {Math.min(PREVIEW_ROWS, rows.length)} rows. Validate the source before importing clinical or reference data.</p>
          <button disabled={busy} onClick={() => void importRows()} className="btn-primary inline-flex items-center gap-2"><Upload className="w-4 h-4" />{busy ? 'Importing…' : `Import ${rows.length.toLocaleString()} rows`}</button>
        </>}
      </div>
      {errors.length > 0 && <div className="card-medical p-5"><h2 className="font-semibold text-critical mb-2">Import errors</h2><ul className="text-xs list-disc pl-5 space-y-1">{errors.slice(0, 50).map((error, i) => <li key={i}>{error}</li>)}</ul></div>}
    </div>
  );
}
