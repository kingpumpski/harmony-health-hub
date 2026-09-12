import { useState } from 'react';
import Papa from 'papaparse';
import * as XLSX from 'xlsx';
import { Database, FileSpreadsheet, Upload, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

type Entity = 'patients' | 'pharmacy_inventory' | 'icd_codes';
interface Row { [key: string]: string | number | null }
const schemas: Record<Entity, { required: string[]; fields: string[] }> = {
  patients: { required: ['first_name', 'last_name'], fields: ['first_name','last_name','date_of_birth','gender','phone','email','address','city','ghana_card_number','blood_group','genotype','allergies','chronic_conditions','insurance_provider','insurance_number','emergency_contact_name','emergency_contact_phone'] },
  pharmacy_inventory: { required: ['drug_name'], fields: ['drug_name','generic_name','strength','form','stock_quantity','reorder_level','unit_price','supplier','expiry_date'] },
  icd_codes: { required: ['code','description'], fields: ['code','description','version','category'] },
};

export default function DataImport() {
  const { user } = useAuth(); const [entity, setEntity] = useState<Entity>('patients'); const [rows, setRows] = useState<Row[]>([]); const [fileName, setFileName] = useState(''); const [busy, setBusy] = useState(false); const [errors, setErrors] = useState<string[]>([]);
  if (user?.role !== 'admin') return <div className="p-8 text-center"><AlertTriangle className="w-10 h-10 text-warning mx-auto mb-2" /><h2 className="font-semibold text-xl">Admin only</h2><p className="text-muted-foreground">Bulk database import requires administrator access.</p></div>;
  const normalize = (value: unknown): string | number | null => value === undefined || value === null || String(value).trim() === '' ? null : typeof value === 'number' ? value : String(value).trim();
  const parse = (file: File) => {
    setFileName(file.name); setErrors([]);
    if (file.name.toLowerCase().endsWith('.csv')) {
      Papa.parse<Row>(file, { header: true, skipEmptyLines: true, transformHeader: h => h.trim().toLowerCase(), complete: result => setRows(result.data.map(r => Object.fromEntries(Object.entries(r).map(([k,v]) => [k, normalize(v)])))) as Row[]), error: e => toast({ title: 'CSV parse failed', description: e.message, variant: 'destructive' }) });
      return;
    }
    const reader = new FileReader(); reader.onload = e => { try { const workbook = XLSX.read(e.target?.result, { type: 'array' }); const sheet = workbook.Sheets[workbook.SheetNames[0]]; const data = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, { defval: null }); setRows(data.map(row => Object.fromEntries(Object.entries(row).map(([k,v]) => [String(k).trim().toLowerCase(), normalize(v)]))) as Row[]); } catch (error) { toast({ title: 'Spreadsheet parse failed', description: error instanceof Error ? error.message : 'Invalid workbook.', variant: 'destructive' }); } }; reader.readAsArrayBuffer(file);
  };
  const validate = (row: Row, index: number) => { for (const field of schemas[entity].required) if (!row[field]) return `Row ${index + 2}: missing ${field}`; if (entity === 'patients' && row.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(row.email))) return `Row ${index + 2}: invalid email`; return null; };
  const importRows = async () => {
    if (!rows.length || !user?.id) return; setBusy(true); const failed: string[] = []; let inserted = 0;
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i]; const validation = validate(row, i); if (validation) { failed.push(validation); continue; }
      try {
        if (entity === 'patients') await supabase.from('patients').insert({ ...row, created_by: user.id } as never).throwOnError();
        if (entity === 'pharmacy_inventory') await supabase.from('pharmacy_inventory').insert({ drug_name: String(row.drug_name), generic_name: row.generic_name, strength: row.strength, form: row.form, stock_quantity: Number(row.stock_quantity ?? 0), reorder_level: Number(row.reorder_level ?? 20), unit_price: Number(row.unit_price ?? 0), supplier: row.supplier, expiry_date: row.expiry_date } as never).throwOnError();
        if (entity === 'icd_codes') await supabase.from('icd_codes').insert({ code: String(row.code), description: String(row.description), version: row.version ?? 'ICD-10', category: row.category } as never).throwOnError();
        inserted++;
      } catch (error) { failed.push(`Row ${i + 2}: ${error instanceof Error ? error.message : 'Insert failed'}`); }
    }
    await supabase.from('bulk_import_jobs').insert({ entity, filename: fileName, total_rows: rows.length, inserted_rows: inserted, failed_rows: failed.length, errors: failed.map(reason => ({ reason })), status: failed.length === rows.length ? 'failed' : 'completed', created_by: user.id } as never);
    setErrors(failed); setBusy(false); setRows([]); setFileName(''); toast({ title: 'Import complete', description: `${inserted}/${rows.length} rows inserted${failed.length ? `; ${failed.length} failed` : ''}.`, variant: failed.length === rows.length ? 'destructive' : 'default' });
  };
  return <div className="space-y-6 animate-fade-in">
    <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Database className="w-6 h-6 text-primary" /> XLSX / CSV Data Import</h1><p className="text-muted-foreground">Controlled bulk import for approved administrative data sets.</p></div>
    <div className="rounded-xl border border-warning/20 bg-warning/5 p-3 text-sm text-muted-foreground">Review the preview before importing. Patient and reference-data imports are audited as bulk import jobs.</div>
    <div className="card-medical p-5 space-y-4"><select value={entity} onChange={e => { setEntity(e.target.value as Entity); setRows([]); setErrors([]); }} className="input-medical w-full"><option value="patients">Patients</option><option value="pharmacy_inventory">Pharmacy inventory</option><option value="icd_codes">ICD-10 codes</option></select><input type="file" accept=".csv,.xlsx,.xls" onChange={e => e.target.files?.[0] && parse(e.target.files[0])} className="input-medical w-full" />{rows.length > 0 && <><p className="text-sm flex items-center gap-2"><FileSpreadsheet className="w-4 h-4" />{fileName} · {rows.length} rows</p><div className="overflow-auto border border-border rounded-xl max-h-80"><table className="text-xs w-full"><thead><tr>{Object.keys(rows[0]).map(k => <th key={k} className="text-left p-2 border-b border-border">{k}</th>)}</tr></thead><tbody>{rows.slice(0,10).map((row,i) => <tr key={i} className="border-b border-border">{Object.keys(rows[0]).map(k => <td key={k} className="p-2 max-w-48 truncate">{String(row[k] ?? '')}</td>)}</tr>)}</tbody></table></div><button disabled={busy} onClick={() => void importRows()} className="btn-primary inline-flex items-center gap-2"><Upload className="w-4 h-4" />{busy ? 'Importing…' : `Import ${rows.length} rows`}</button></>}</div>
    {errors.length > 0 && <div className="card-medical p-5"><h2 className="font-semibold text-critical mb-2">Import errors</h2><ul className="text-xs list-disc pl-5 space-y-1">{errors.slice(0,50).map((e,i) => <li key={i}>{e}</li>)}</ul></div>}
  </div>;
}
