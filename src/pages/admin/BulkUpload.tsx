// @ts-nocheck -- generated database types are stale relative to applied migrations; regenerate types to remove.
import { useEffect, useRef, useState } from 'react';
import Papa from 'papaparse';
import RefreshButton from '@/components/ui/RefreshButton';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Upload, Database, FileSpreadsheet, CheckCircle2, AlertTriangle, Download, XCircle, SkipForward } from 'lucide-react';
import { playSuccessSound } from '@/lib/sounds';
import { notifyMasterDataChanged } from '@/lib/masterDataEvents';
import { IMPORT_SCHEMAS, rowsFromMatrix, prepareImport, chunk, withRetry } from '@/lib/bulkImport.mjs';
import { MAX_SPREADSHEET_FILE_BYTES, MAX_SPREADSHEET_ROWS } from '@/lib/spreadsheetImport.mjs';

type Entity = keyof typeof IMPORT_SCHEMAS;
type Issue = { row: number; reason: string };
interface JobLog { id: string; entity_type: string; file_name: string | null; total_rows: number; successful_rows: number; failed_rows: number; status: string; created_at: string }
const CHUNK = 200;
const ADMIN_ROLES = ['admin', 'it_admin', 'system_superuser'];
const transient = (e: unknown) => /fetch|network|timeout|Failed to send|5\d\d|rate/i.test(String((e as Error)?.message ?? e));

export default function BulkUpload() {
  const { user } = useAuth();
  const isAdmin = ADMIN_ROLES.includes(user?.role ?? '');
  const [entity, setEntity] = useState<Entity>('patients');
  const [filename, setFilename] = useState('');
  const [format, setFormat] = useState<'csv' | 'xlsx' | 'xls'>('csv');
  const [prep, setPrep] = useState<ReturnType<typeof prepareImport> | null>(null);
  const [totalRows, setTotalRows] = useState(0);
  const [importing, setImporting] = useState(false);
  const [progress, setProgress] = useState({ done: 0, total: 0 });
  const [result, setResult] = useState<{ inserted: number; skipped: Issue[]; failed: Issue[] } | null>(null);
  const [history, setHistory] = useState<JobLog[]>([]);
  const fileRef = useRef<HTMLInputElement>(null);
  const schema = IMPORT_SCHEMAS[entity];

  const loadHistory = async () => {
    const { data } = await supabase.from('bulk_import_jobs').select('id,entity_type,file_name,total_rows,successful_rows,failed_rows,status,created_at').order('created_at', { ascending: false }).limit(20);
    setHistory((data ?? []) as JobLog[]);
  };
  useEffect(() => { if (isAdmin) void loadHistory(); }, [isAdmin]);

  const reset = () => { setPrep(null); setFilename(''); setTotalRows(0); setResult(null); if (fileRef.current) fileRef.current.value = ''; };

  const ingest = (matrix: unknown[][], name: string, fmt: 'csv' | 'xlsx' | 'xls') => {
    const { headers, rows } = rowsFromMatrix(matrix, entity);
    if (rows.length > MAX_SPREADSHEET_ROWS) throw new Error(`Files are limited to ${MAX_SPREADSHEET_ROWS.toLocaleString()} rows.`);
    if (!rows.length) throw new Error('The file has a header row but no data rows.');
    const p = prepareImport(entity, rows, headers);
    setFilename(name); setFormat(fmt); setTotalRows(rows.length); setPrep(p); setResult(null);
    toast({ title: 'File checked', description: `${p.valid.length} of ${rows.length} rows ready to import${p.issues.length ? ` · ${p.issues.length} need attention` : ''}.` });
  };

  const handleFile = async (file: File) => {
    setResult(null); setPrep(null);
    try {
      if (file.size > MAX_SPREADSHEET_FILE_BYTES) throw new Error(`Files are limited to ${MAX_SPREADSHEET_FILE_BYTES / 1024 / 1024} MB.`);
      const lower = file.name.toLowerCase();
      if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
        const text = (await file.text()).replace(/^\uFEFF/, '');
        const parsed = Papa.parse<string[]>(text, { skipEmptyLines: 'greedy' });
        if (parsed.errors.length && !parsed.data.length) throw new Error(parsed.errors[0].message);
        ingest(parsed.data, file.name, 'csv');
      } else if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
        const XLSX = await import('xlsx');
        const wb = XLSX.read(await file.arrayBuffer(), { type: 'array', cellDates: true, cellFormula: false, bookVBA: false });
        // Prefer the "Data" sheet of our template, otherwise the first sheet with the required columns.
        const names = [...wb.SheetNames].sort((a, b) => (b.toLowerCase() === 'data' ? 1 : 0) - (a.toLowerCase() === 'data' ? 1 : 0));
        let lastErr: Error | null = null;
        for (const n of names) {
          if (n.toLowerCase() === 'instructions') continue;
          const matrix = XLSX.utils.sheet_to_json(wb.Sheets[n], { header: 1, defval: null, raw: true, blankrows: false });
          try { ingest(matrix as unknown[][], file.name, lower.endsWith('.xls') ? 'xls' : 'xlsx'); return; } catch (e) { lastErr = e as Error; }
        }
        throw lastErr ?? new Error('The workbook contains no usable worksheet.');
      } else throw new Error('Choose a CSV, XLSX or XLS file.');
    } catch (e) {
      reset();
      toast({ title: 'Could not read file', description: (e as Error).message, variant: 'destructive' });
    }
  };

  const downloadTemplate = async (kind: 'csv' | 'xlsx') => {
    const cols = [...schema.required, ...schema.optional];
    if (kind === 'csv') {
      const csv = Papa.unparse({ fields: cols, data: [cols.map((c) => schema.sample[c] ?? '')] });
      const url = URL.createObjectURL(new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8' }));
      const a = document.createElement('a'); a.href = url; a.download = `${entity}_template.csv`; a.click(); URL.revokeObjectURL(url);
      return;
    }
    const XLSX = await import('xlsx');
    const wb = XLSX.utils.book_new();
    const data = XLSX.utils.aoa_to_sheet([cols.map((c) => (schema.required.includes(c) ? `${c}*` : c)), cols.map((c) => schema.sample[c] ?? '')]);
    data['!cols'] = cols.map((c) => ({ wch: Math.max(14, c.length + 4) }));
    XLSX.utils.book_append_sheet(wb, data, 'Data');
    const help = [['Column', 'Required', 'Format'], ...cols.map((c) => [c, schema.required.includes(c) ? 'Yes' : 'No', ({ date: 'Date: YYYY-MM-DD or DD/MM/YYYY', int: 'Whole number ≥ 0', money: 'Amount ≥ 0 (GHS)', email: 'Valid email', gender: 'male / female / other', phone: 'Phone number', upper: 'Text (auto upper-case)', lower: 'Text' } as Record<string, string>)[schema.types[c]] ?? 'Text'])];
    help.push([], ['Fill in the "Data" sheet. Replace the sample row. Columns marked * are required. Existing records are detected and skipped automatically.']);
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(help), 'Instructions');
    XLSX.writeFile(wb, `${entity}_template.xlsx`);
  };

  const downloadIssues = () => {
    const all = [...(prep?.issues ?? []), ...(result?.failed ?? []).map((i) => ({ ...i, reason: 'Server: ' + i.reason })), ...(result?.skipped ?? []).map((i) => ({ ...i, reason: 'Skipped: ' + i.reason }))].sort((a, b) => a.row - b.row);
    const csv = Papa.unparse(all.map((i) => ({ row: i.row, issue: i.reason })));
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }));
    const a = document.createElement('a'); a.href = url; a.download = `${entity}_import_issues.csv`; a.click(); URL.revokeObjectURL(url);
  };

  const importStaffRow = async (row: Record<string, unknown>) => {
    const { data, error } = await supabase.functions.invoke('admin-create-user', { body: { email: row.email, firstName: row.first_name, lastName: row.last_name, phone: row.phone ?? '', department: row.department ?? '', specialization: row.specialization ?? '', role: row.role, onboarding: 'invite' } });
    if (error) throw error; if (data?.error) throw Object.assign(new Error(data.error), { permanent: true });
  };

  const performImport = async () => {
    if (!prep?.valid.length || importing) return;
    setImporting(true);
    const failed: Issue[] = []; const skipped: Issue[] = []; let inserted = 0;
    try {
      if (entity === 'staff') {
        setProgress({ done: 0, total: prep.valid.length });
        for (const [i, row] of prep.valid.entries()) {
          try { await withRetry(() => importStaffRow(row), { isRetryable: (e) => !e?.permanent && transient(e) }); inserted++; }
          catch (e) { const m = String((e as Error).message); (/already|exists|registered/i.test(m) ? skipped : failed).push({ row: row.__row, reason: m }); }
          setProgress({ done: i + 1, total: prep.valid.length });
        }
      } else {
        const batches = chunk(prep.valid, CHUNK);
        setProgress({ done: 0, total: batches.length });
        for (const [i, batch] of batches.entries()) {
          try {
            const data = await withRetry(async () => {
              const { data, error } = await supabase.functions.invoke('admin-bulk-import', { body: { action: 'import_rows', entity, source_format: format, filename: batches.length > 1 ? `${filename} (part ${i + 1}/${batches.length})` : filename, rows: batch } });
              if (error) throw error; if (data?.error) throw Object.assign(new Error(data.error), { permanent: true });
              return data;
            }, { isRetryable: (e) => !e?.permanent && transient(e) });
            inserted += Number(data?.inserted_rows ?? 0);
            failed.push(...(data?.errors ?? [])); skipped.push(...(data?.skipped ?? []));
          } catch (e) {
            // A whole batch failed after retries: report every row so nothing is silently lost.
            batch.forEach((r) => failed.push({ row: r.__row, reason: `Not imported: ${(e as Error).message}` }));
          }
          setProgress({ done: i + 1, total: batches.length });
        }
      }
      setResult({ inserted, skipped, failed });
      toast({ title: failed.length ? 'Import finished with problems' : 'Import complete', description: `${inserted} added · ${skipped.length} already existed · ${failed.length} failed`, variant: inserted === 0 && failed.length ? 'destructive' : 'default' });
      if (inserted) { playSuccessSound(); notifyMasterDataChanged(entity === 'patients' ? 'patients' : entity === 'pharmacy_inventory' ? 'pharmacy' : entity === 'icd_codes' ? 'diagnoses' : 'all'); }
      setPrep((p) => (p ? { ...p, valid: [] } : p));
      await loadHistory();
    } finally { setImporting(false); }
  };

  if (!isAdmin) return <div className="p-8 text-center"><AlertTriangle className="w-10 h-10 text-warning mx-auto mb-2" /><h2 className="font-heading text-xl">Admin only</h2><p className="text-muted-foreground text-sm">Administrator privileges are required.</p></div>;

  const preview = prep?.valid.slice(0, 10) ?? [];
  const cols = [...schema.required, ...schema.optional].filter((c) => preview.some((r) => r[c] !== undefined));
  const issueCount = (prep?.issues.length ?? 0) + (result?.failed.length ?? 0) + (result?.skipped.length ?? 0);

  return <div className="space-y-6 animate-fade-in">
    <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Database className="w-6 h-6 text-primary" />Bulk Database Upload</h1><p className="text-muted-foreground">Download a template, fill it in, then upload it. Every row is checked before anything is saved, and records that already exist are skipped.</p></div>
    <div className="card-medical p-5 space-y-4">
      <div className="grid md:grid-cols-2 gap-3">
        <label className="text-sm"><span className="font-medium">What are you importing?</span><select value={entity} onChange={(e) => { setEntity(e.target.value as Entity); reset(); }} className="input-medical w-full mt-1">{Object.entries(IMPORT_SCHEMAS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}</select></label>
        <div className="flex items-end gap-2 flex-wrap"><button onClick={() => void downloadTemplate('xlsx')} className="btn-ghost flex items-center gap-2"><Download className="w-4 h-4" />Excel template</button><button onClick={() => void downloadTemplate('csv')} className="btn-ghost flex items-center gap-2"><Download className="w-4 h-4" />CSV template</button></div>
      </div>
      <div className="rounded-lg bg-muted/40 p-3 text-xs space-y-1"><p><strong>Required:</strong> {schema.required.join(', ')}</p><p><strong>Optional:</strong> {schema.optional.join(', ')}</p><p className="text-muted-foreground">Common column names (e.g. "Surname", "DOB", "Qty") and dates like 12/04/1990 are recognised automatically.</p></div>
      <input ref={fileRef} type="file" accept=".csv,.xlsx,.xls,text/csv" onChange={(e) => e.target.files?.[0] && void handleFile(e.target.files[0])} className="input-medical w-full" disabled={importing} />
      {prep && <div className="space-y-3">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-sm">
          <div className="rounded-lg border border-border p-2"><p className="text-xs text-muted-foreground">Rows in file</p><p className="font-semibold">{totalRows}</p></div>
          <div className="rounded-lg border border-border p-2"><p className="text-xs text-muted-foreground">Ready</p><p className="font-semibold text-success">{prep.valid.length}</p></div>
          <div className="rounded-lg border border-border p-2"><p className="text-xs text-muted-foreground">Need fixing</p><p className="font-semibold text-critical">{prep.issues.length - prep.duplicates}</p></div>
          <div className="rounded-lg border border-border p-2"><p className="text-xs text-muted-foreground">Repeated in file</p><p className="font-semibold text-warning">{prep.duplicates}</p></div>
        </div>
        {prep.ignoredColumns.length > 0 && <p className="text-xs text-warning">Ignored unknown columns: {prep.ignoredColumns.join(', ')}</p>}
        <p className="text-sm flex items-center gap-2"><FileSpreadsheet className="w-4 h-4" /><strong>{filename}</strong></p>
        {preview.length > 0 && <div className="overflow-x-auto rounded-lg border border-border"><table className="text-xs w-full"><thead className="bg-muted/40"><tr><th className="px-2 py-1 text-left">Row</th>{cols.map((h) => <th key={h} className="text-left px-2 py-1 font-medium">{h}</th>)}</tr></thead><tbody>{preview.map((r) => <tr key={r.__row} className="border-t border-border"><td className="px-2 py-1 text-muted-foreground">{r.__row}</td>{cols.map((h) => <td key={h} className="px-2 py-1 truncate max-w-[200px]">{String(r[h] ?? '')}</td>)}</tr>)}</tbody></table></div>}
        {importing && <div className="space-y-1"><div className="h-2 rounded bg-muted overflow-hidden"><div className="h-full bg-primary transition-all" style={{ width: `${progress.total ? (progress.done / progress.total) * 100 : 0}%` }} /></div><p className="text-xs text-muted-foreground">Importing… {progress.done}/{progress.total} {entity === 'staff' ? 'accounts' : 'batches'}. Keep this page open.</p></div>}
        <div className="flex gap-2 flex-wrap">
          <button onClick={() => void performImport()} disabled={importing || !prep.valid.length} className="btn-primary flex items-center gap-2"><Upload className="w-4 h-4" />{importing ? 'Importing…' : `Import ${prep.valid.length} rows`}</button>
          <button onClick={reset} disabled={importing} className="btn-ghost">Clear</button>
        </div>
      </div>}
    </div>
    {result && <div className="card-medical p-5 grid grid-cols-3 gap-3 text-sm">
      <div className="flex items-center gap-2"><CheckCircle2 className="w-5 h-5 text-success" />{result.inserted} added</div>
      <div className="flex items-center gap-2"><SkipForward className="w-5 h-5 text-warning" />{result.skipped.length} already existed</div>
      <div className="flex items-center gap-2"><XCircle className="w-5 h-5 text-critical" />{result.failed.length} failed</div>
    </div>}
    {issueCount > 0 && <div className="card-medical p-5"><div className="flex justify-between items-center mb-2"><h2 className="font-semibold">Rows needing attention</h2><button onClick={downloadIssues} className="btn-ghost text-xs flex items-center gap-1"><Download className="w-3 h-3" />Download list</button></div>
      <ul className="text-xs list-disc pl-5 space-y-0.5 max-h-72 overflow-y-auto">{[...(prep?.issues ?? []), ...(result?.failed ?? []), ...(result?.skipped ?? [])].slice(0, 200).map((e, i) => <li key={i}>{e.row ? `Row ${e.row}: ` : ''}{e.reason}</li>)}</ul></div>}
    <div className="card-medical p-5"><div className="flex justify-between items-center mb-3"><h2 className="font-semibold">Import history</h2><RefreshButton onClick={() => void loadHistory()} label="Refresh import history" /></div>
      {history.length === 0 && <p className="text-xs text-muted-foreground">No imports yet.</p>}
      {history.map((h) => <div key={h.id} className="rounded-xl border border-border p-3 text-sm mt-2"><div className="flex justify-between gap-2"><span className="font-medium flex items-center gap-2">{h.status === 'completed' ? <CheckCircle2 className="w-4 h-4 text-success" /> : <AlertTriangle className="w-4 h-4 text-warning" />}{h.entity_type} — {h.file_name ?? 'untitled'}</span><span className="text-xs text-muted-foreground">{new Date(h.created_at).toLocaleString()}</span></div><p className="text-xs text-muted-foreground mt-1">{h.successful_rows}/{h.total_rows} added · {h.failed_rows} failed</p></div>)}
    </div>
  </div>;
}
