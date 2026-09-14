import { useState } from 'react';
import Papa from 'papaparse';
import * as XLSX from 'xlsx';
import { Database, FileSpreadsheet, Upload, AlertTriangle, ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

type Entity = 'patients' | 'pharmacy_inventory' | 'icd_codes' | 'diagnosis_workbook';
interface Row { [key: string]: string | number | null }
interface SheetAssessment { name: string; rows: number; columns: string[]; missingHeaders: string[]; duplicateRows: number; preview: Row[] }
const schemas: Record<Exclude<Entity, 'diagnosis_workbook'>, { required: string[]; fields: string[] }> = {
  patients: { required: ['first_name', 'last_name'], fields: ['first_name','last_name','date_of_birth','gender','phone','email','address','city','ghana_card_number','blood_group','genotype','allergies','chronic_conditions','insurance_provider','insurance_number','emergency_contact_name','emergency_contact_phone'] },
  pharmacy_inventory: { required: ['drug_name'], fields: ['drug_name','generic_name','strength','form','stock_quantity','reorder_level','unit_price','supplier','expiry_date'] },
  icd_codes: { required: ['code','description'], fields: ['code','description','version','category'] },
};
const normalize = (value: unknown): string | number | null => value === undefined || value === null || String(value).trim() === '' ? null : typeof value === 'number' ? value : String(value).trim();
const normalizeRows = (data: Record<string, unknown>[]) => data.map(row => Object.fromEntries(Object.entries(row).map(([k,v]) => [String(k).trim().toLowerCase(), normalize(v)]))) as Row[];

export default function DataImport() {
  const { user } = useAuth(); const [entity, setEntity] = useState<Entity>('patients'); const [rows, setRows] = useState<Row[]>([]); const [fileName, setFileName] = useState(''); const [busy, setBusy] = useState(false); const [errors, setErrors] = useState<string[]>([]); const [assessment, setAssessment] = useState<SheetAssessment[]>([]);
  if (user?.role !== 'admin') return <div className="p-8 text-center"><AlertTriangle className="w-10 h-10 text-warning mx-auto mb-2" /><h2 className="font-semibold text-xl">Admin only</h2><p className="text-muted-foreground">Bulk database import requires administrator access.</p></div>;
  const validate = (row: Row, index: number) => { for (const field of schemas[entity as Exclude<Entity, 'diagnosis_workbook'>].required) if (!row[field]) return `Row ${index + 2}: missing ${field}`; if (entity === 'patients' && row.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(row.email))) return `Row ${index + 2}: invalid email`; return null; };
  const assessWorkbook = (file: File) => {
    setFileName(file.name); setRows([]); setErrors([]); setAssessment([]);
    if (!/\.(xlsx|xls)$/i.test(file.name)) { toast({ title: 'Diagnosis assessment requires Excel', description: 'Select an .xlsx or .xls workbook.', variant: 'destructive' }); return; }
    const reader = new FileReader(); reader.onload = async e => { try {
      const workbook = XLSX.read(e.target?.result, { type: 'array', cellDates: true });
      const sheets: SheetAssessment[] = workbook.SheetNames.map(name => {
        const sheet = workbook.Sheets[name]; const raw = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, { defval: null }); const data = normalizeRows(raw);
        const columns = data.length ? Object.keys(data[0]) : (XLSX.utils.sheet_to_json<string[]>(sheet, { header: 1, defval: null })[0] || []).map(String).map(v => v.trim().toLowerCase()).filter(Boolean);
        const seen = new Set<string>(); let duplicateRows = 0; for (const row of data) { const key = JSON.stringify(row); if (seen.has(key)) duplicateRows++; else seen.add(key); }
        const missingHeaders = columns.length === 0 ? ['no header row detected'] : [];
        return { name, rows: data.length, columns, missingHeaders, duplicateRows, preview: data.slice(0, 5) };
      });
      setAssessment(sheets);
      const totalRows = sheets.reduce((sum, sheet) => sum + sheet.rows, 0);
      const duplicateRows = sheets.reduce((sum, sheet) => sum + sheet.duplicateRows, 0);
      const validationErrors = sheets.flatMap(sheet => sheet.missingHeaders.map(reason => ({ sheet: sheet.name, reason })));
      const { error: batchError } = await supabase.from('diagnosis_import_batches').insert({ file_name: file.name, source_format: file.name.toLowerCase().endsWith('.xls') ? 'xls' : 'xlsx', assessment_only: true, status: 'assessed', total_sheets: sheets.length, total_rows: totalRows, duplicate_rows: duplicateRows, validation_errors: validationErrors, sheet_assessments: sheets.map(({ preview, ...summary }) => summary), created_by: user?.id ?? null } as never);
      if (batchError) console.warn('Diagnosis assessment audit could not be persisted', batchError);
      toast({ title: 'Workbook assessed', description: `${sheets.length} worksheet${sheets.length === 1 ? '' : 's'} detected; ${totalRows} rows assessed. No diagnosis records were changed.` });
    } catch (error) { toast({ title: 'Workbook assessment failed', description: error instanceof Error ? error.message : 'Invalid workbook.', variant: 'destructive' }); } };
    reader.readAsArrayBuffer(file);
  };
  const parse = (file: File) => {
    setFileName(file.name); setErrors([]); setAssessment([]);
    if (file.name.toLowerCase().endsWith('.csv')) { Papa.parse<Row>(file, { header: true, skipEmptyLines: true, transformHeader: h => h.trim().toLowerCase(), complete: result => setRows(result.data.map(r => Object.fromEntries(Object.entries(r).map(([k,v]) => [k, normalize(v)]))) as Row[]), error: e => toast({ title: 'CSV parse failed', description: e.message, variant: 'destructive' }) }); return; }
    const reader = new FileReader(); reader.onload = e => { try { const workbook = XLSX.read(e.target?.result, { type: 'array' }); const sheet = workbook.Sheets[workbook.SheetNames[0]]; setRows(normalizeRows(XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, { defval: null }))); } catch (error) { toast({ title: 'Spreadsheet parse failed', description: error instanceof Error ? error.message : 'Invalid workbook.', variant: 'destructive' }); } }; reader.readAsArrayBuffer(file);
  };
  const importRows = async () => {
    if (!rows.length || !user?.id || entity === 'diagnosis_workbook') return; setBusy(true); const failed: string[] = []; let inserted = 0;
    for (let i = 0; i < rows.length; i++) { const row = rows[i]; const validation = validate(row, i); if (validation) { failed.push(validation); continue; } try {
      if (entity === 'patients') await supabase.from('patients').insert({ ...row, created_by: user.id } as never).throwOnError();
      if (entity === 'pharmacy_inventory') await supabase.from('pharmacy_inventory').insert({ drug_name: String(row.drug_name), generic_name: row.generic_name, strength: row.strength, form: row.form, stock_quantity: Number(row.stock_quantity ?? 0), reorder_level: Number(row.reorder_level ?? 20), unit_price: Number(row.unit_price ?? 0), supplier: row.supplier, expiry_date: row.expiry_date } as never).throwOnError();
      if (entity === 'icd_codes') await supabase.from('icd_codes').insert({ code: String(row.code), description: String(row.description), version: row.version ?? 'ICD-10', category: row.category } as never).throwOnError(); inserted++;
    } catch (error) { failed.push(`Row ${i + 2}: ${error instanceof Error ? error.message : 'Insert failed'}`); } }
    const sourceFormat = fileName.toLowerCase().endsWith('.csv') ? 'csv' : 'xlsx'; const jobStatus = failed.length === rows.length ? 'failed' : failed.length > 0 ? 'completed_with_errors' : 'completed';
    const { error: auditError } = await supabase.from('bulk_import_jobs').insert({ entity_type: entity, source_format: sourceFormat, file_name: fileName || null, total_rows: rows.length, successful_rows: inserted, failed_rows: failed.length, errors: failed.map(reason => ({ reason })), status: jobStatus, created_by: user.id, completed_at: new Date().toISOString() } as never);
    if (auditError) toast({ title: 'Import audit warning', description: auditError.message }); setErrors(failed); setBusy(false); setRows([]); setFileName(''); toast({ title: 'Import complete', description: `${inserted}/${rows.length} rows inserted${failed.length ? `; ${failed.length} failed` : ''}.`, variant: failed.length === rows.length ? 'destructive' : 'default' });
  };
  return <div className="space-y-6 animate-fade-in">
    <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Database className="w-6 h-6 text-primary" /> XLSX / CSV Data Import</h1><p className="text-muted-foreground">Controlled bulk import for approved administrative data sets.</p></div>
    <div className="rounded-xl border border-warning/20 bg-warning/5 p-3 text-sm text-muted-foreground">Review the preview before importing. Diagnosis workbooks are assessment-only until a validated diagnosis import pipeline is approved.</div>
    <div className="card-medical p-5 space-y-4"><select value={entity} onChange={e => { setEntity(e.target.value as Entity); setRows([]); setErrors([]); setAssessment([]); }} className="input-medical w-full"><option value="patients">Patients</option><option value="pharmacy_inventory">Pharmacy inventory</option><option value="icd_codes">ICD-10 codes</option><option value="diagnosis_workbook">Diagnosis workbook — assess only</option></select><input type="file" accept=".csv,.xlsx,.xls" onChange={e => { const file = e.target.files?.[0]; if (!file) return; entity === 'diagnosis_workbook' ? assessWorkbook(file) : parse(file); }} className="input-medical w-full" />{entity === 'diagnosis_workbook' && assessment.length > 0 && <div className="space-y-3"><div className="flex items-center gap-2 text-sm font-medium"><ShieldCheck className="w-4 h-4" />Read-only workbook assessment — database unchanged</div>{assessment.map(sheet => <div key={sheet.name} className="border border-border rounded-xl p-3"><div className="flex justify-between gap-3"><strong>{sheet.name}</strong><span className="text-xs text-muted-foreground">{sheet.rows} rows · {sheet.columns.length} columns · {sheet.duplicateRows} duplicate rows</span></div><p className="text-xs text-muted-foreground mt-1">Columns: {sheet.columns.join(', ') || 'none detected'}</p>{sheet.missingHeaders.length > 0 && <p className="text-xs text-critical mt-1">{sheet.missingHeaders.join(', ')}</p>}{sheet.preview.length > 0 && <div className="overflow-auto mt-2"><table className="text-xs w-full"><thead><tr>{sheet.columns.map(k => <th key={k} className="text-left p-1 border-b border-border">{k}</th>)}</tr></thead><tbody>{sheet.preview.map((row,i) => <tr key={i}>{sheet.columns.map(k => <td key={k} className="p-1 max-w-48 truncate">{String(row[k] ?? '')}</td>)}</tr>)}</tbody></table></div>}</div>)}</div>}{rows.length > 0 && <><p className="text-sm flex items-center gap-2"><FileSpreadsheet className="w-4 h-4" />{fileName} · {rows.length} rows</p><div className="overflow-auto border border-border rounded-xl max-h-80"><table className="text-xs w-full"><thead><tr>{Object.keys(rows[0]).map(k => <th key={k} className="text-left p-2 border-b border-border">{k}</th>)}</tr></thead><tbody>{rows.slice(0,10).map((row,i) => <tr key={i} className="border-b border-border">{Object.keys(rows[0]).map(k => <td key={k} className="p-2 max-w-48 truncate">{String(row[k] ?? '')}</td>)}</tr>)}</tbody></table></div><button disabled={busy} onClick={() => void importRows()} className="btn-primary inline-flex items-center gap-2"><Upload className="w-4 h-4" />{busy ? 'Importing…' : `Import ${rows.length} rows`}</button></>}</div>
    {errors.length > 0 && <div className="card-medical p-5"><h2 className="font-semibold text-critical mb-2">Import errors</h2><ul className="text-xs list-disc pl-5 space-y-1">{errors.slice(0,50).map((e,i) => <li key={i}>{e}</li>)}</ul></div>}
  </div>;
}