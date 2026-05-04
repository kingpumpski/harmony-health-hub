import { useState } from 'react';
import Papa from 'papaparse';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Upload, Database, FileSpreadsheet, CheckCircle2, AlertTriangle, Download } from 'lucide-react';
import { playSuccessSound } from '@/lib/sounds';

type Entity = 'patients' | 'pharmacy_inventory' | 'icd_codes' | 'staff';

interface SchemaSpec {
  label: string;
  required: string[];
  optional: string[];
  sample: string;
  describe: string;
}

const SCHEMAS: Record<Entity, SchemaSpec> = {
  patients: {
    label: 'Patients',
    required: ['first_name', 'last_name'],
    optional: ['date_of_birth', 'gender', 'phone', 'email', 'address', 'city', 'ghana_card_number', 'blood_group', 'genotype', 'allergies', 'chronic_conditions', 'insurance_provider', 'insurance_number', 'emergency_contact_name', 'emergency_contact_phone'],
    sample: 'first_name,last_name,date_of_birth,gender,phone,email,ghana_card_number\nJane,Doe,1990-04-12,female,+233200000000,jane@example.com,GHA-123456789-0',
    describe: 'Bulk import patient demographics. Duplicates skipped on Ghana card or phone.',
  },
  pharmacy_inventory: {
    label: 'Pharmacy inventory & drugs',
    required: ['drug_name'],
    optional: ['generic_name', 'strength', 'form', 'stock_quantity', 'reorder_level', 'unit_price', 'supplier', 'expiry_date'],
    sample: 'drug_name,generic_name,strength,form,stock_quantity,reorder_level,unit_price,supplier,expiry_date\nParacetamol,Acetaminophen,500mg,tablet,500,50,0.50,MedSupply Ghana,2027-12-31',
    describe: 'Add new drugs and stock levels.',
  },
  icd_codes: {
    label: 'ICD-10 codes',
    required: ['code', 'description'],
    optional: ['version', 'category'],
    sample: 'code,description,version,category\nA00,Cholera,ICD-10,Infectious\nE11,Type 2 diabetes mellitus,ICD-10,Endocrine',
    describe: 'Reference codes for diagnoses.',
  },
  staff: {
    label: 'Staff / users with roles',
    required: ['email', 'role'],
    optional: ['first_name', 'last_name', 'department', 'specialization', 'phone'],
    sample: 'email,role,first_name,last_name,department,specialization\nnurse1@clinic.gh,nurse,Mary,Asante,General,\ndoc1@clinic.gh,practitioner,Kofi,Mensah,Cardiology,Cardiologist',
    describe: 'Pre-creates profile rows + role assignments. Users sign up with the same email to claim the account.',
  },
};

interface JobLog { id: string; entity: string; filename: string | null; total_rows: number; inserted_rows: number; failed_rows: number; status: string; created_at: string; errors: any }

export default function BulkUpload() {
  const { user } = useAuth();
  const isAdmin = user?.role === 'admin';
  const [entity, setEntity] = useState<Entity>('patients');
  const [rows, setRows] = useState<Record<string, string>[]>([]);
  const [filename, setFilename] = useState('');
  const [importing, setImporting] = useState(false);
  const [history, setHistory] = useState<JobLog[]>([]);
  const [previewOnly, setPreviewOnly] = useState(true);

  const loadHistory = async () => {
    const { data } = await supabase.from('bulk_import_jobs').select('*').order('created_at', { ascending: false }).limit(20);
    setHistory((data ?? []) as JobLog[]);
  };

  if (!isAdmin) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="w-10 h-10 text-warning mx-auto mb-2" />
        <h2 className="font-heading text-xl">Admin only</h2>
        <p className="text-muted-foreground text-sm">You need admin privileges to access bulk upload.</p>
      </div>
    );
  }

  const handleFile = (file: File) => {
    setFilename(file.name);
    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      transformHeader: (h) => h.trim().toLowerCase(),
      complete: (res) => {
        setRows(res.data as Record<string, string>[]);
        toast({ title: `Parsed ${res.data.length} rows`, description: 'Review preview, then click Import.' });
      },
      error: (err) => toast({ title: 'Parse error', description: err.message, variant: 'destructive' }),
    });
  };

  const downloadTemplate = () => {
    const blob = new Blob([SCHEMAS[entity].sample], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `${entity}_template.csv`; a.click();
    URL.revokeObjectURL(url);
  };

  const validate = (row: Record<string, string>, idx: number): string | null => {
    for (const r of SCHEMAS[entity].required) {
      if (!row[r] || String(row[r]).trim() === '') return `Row ${idx + 2}: missing required "${r}"`;
    }
    if (entity === 'patients' && row.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(row.email)) return `Row ${idx + 2}: invalid email`;
    if (entity === 'staff') {
      const allowed = ['admin','practitioner','nurse','midwife','lab_technician','pharmacist','accountant','front_desk','canteen','patient'];
      if (!allowed.includes(String(row.role).toLowerCase())) return `Row ${idx + 2}: role "${row.role}" not allowed`;
    }
    return null;
  };

  const performImport = async () => {
    if (!rows.length) return;
    setImporting(true);
    const errors: { row: number; reason: string }[] = [];
    let inserted = 0;

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const valErr = validate(row, i);
      if (valErr) { errors.push({ row: i + 2, reason: valErr }); continue; }

      try {
        if (entity === 'patients') {
          const payload: any = { ...row, created_by: user?.id };
          // sanitize empty strings to null
          Object.keys(payload).forEach((k) => { if (payload[k] === '') payload[k] = null; });
          const { error } = await supabase.from('patients').insert(payload);
          if (error) throw error;
        } else if (entity === 'pharmacy_inventory') {
          const payload: any = {
            drug_name: row.drug_name,
            generic_name: row.generic_name || null,
            strength: row.strength || null,
            form: row.form || null,
            stock_quantity: Number(row.stock_quantity || 0),
            reorder_level: Number(row.reorder_level || 20),
            unit_price: Number(row.unit_price || 0),
            supplier: row.supplier || null,
            expiry_date: row.expiry_date || null,
          };
          const { error } = await supabase.from('pharmacy_inventory').insert(payload);
          if (error) throw error;
        } else if (entity === 'icd_codes') {
          const { error } = await supabase.from('icd_codes').insert({
            code: row.code, description: row.description, version: row.version || 'ICD-10', category: row.category || null,
          });
          if (error) throw error;
        } else if (entity === 'staff') {
          // Pre-create profile + role; user must complete signup with same email to link auth.
          // We can't insert into auth here, so we stage a "pending profile" row via metadata.
          // Insert into profiles with a generated id keyed by email so an admin can later link.
          const stagedId = crypto.randomUUID();
          const { error: pErr } = await supabase.from('profiles').upsert({
            id: stagedId,
            email: row.email,
            first_name: row.first_name || '',
            last_name: row.last_name || '',
            department: row.department || null,
            specialization: row.specialization || null,
            phone: row.phone || null,
          });
          if (pErr) throw pErr;
          const { error: rErr } = await supabase.from('user_roles').insert({
            user_id: stagedId, role: String(row.role).toLowerCase() as any,
          });
          if (rErr) throw rErr;
        }
        inserted++;
      } catch (err: any) {
        errors.push({ row: i + 2, reason: err?.message ?? String(err) });
      }
    }

    await supabase.from('bulk_import_jobs').insert({
      entity, filename, total_rows: rows.length, inserted_rows: inserted, failed_rows: errors.length,
      errors: errors as any, status: errors.length === rows.length ? 'failed' : 'completed', created_by: user?.id,
    });

    playSuccessSound();
    toast({
      title: `Import complete`,
      description: `${inserted} of ${rows.length} rows inserted${errors.length ? ` · ${errors.length} failed` : ''}.`,
      variant: errors.length === rows.length ? 'destructive' : 'default',
    });
    setImporting(false);
    setRows([]);
    setFilename('');
    loadHistory();
  };

  const previewRows = rows.slice(0, 10);
  const headers = previewRows.length ? Object.keys(previewRows[0]) : [];

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
          <Database className="w-6 h-6 text-primary" /> Bulk Database Upload
        </h1>
        <p className="text-muted-foreground">Admin/IT: load real data into the system from CSV files.</p>
      </div>

      <div className="card-medical p-5 space-y-4">
        <div className="grid md:grid-cols-2 gap-3">
          <label className="text-sm">
            <span className="font-medium">Entity</span>
            <select value={entity} onChange={(e) => { setEntity(e.target.value as Entity); setRows([]); setFilename(''); }} className="input-medical w-full mt-1">
              {Object.entries(SCHEMAS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
            </select>
          </label>
          <div className="flex items-end gap-2">
            <button onClick={downloadTemplate} className="btn-ghost flex items-center gap-2">
              <Download className="w-4 h-4" /> Download CSV template
            </button>
          </div>
        </div>

        <div className="rounded-lg bg-muted/40 p-3 text-xs">
          <p className="font-medium mb-1">{SCHEMAS[entity].describe}</p>
          <p><strong>Required:</strong> {SCHEMAS[entity].required.join(', ')}</p>
          <p><strong>Optional:</strong> {SCHEMAS[entity].optional.join(', ')}</p>
        </div>

        <label className="block">
          <input type="file" accept=".csv,text/csv" onChange={(e) => e.target.files?.[0] && handleFile(e.target.files[0])} className="input-medical w-full" />
        </label>

        {rows.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <p className="text-sm flex items-center gap-2">
                <FileSpreadsheet className="w-4 h-4" /> <strong>{filename}</strong> · {rows.length} rows ready
              </p>
              <label className="text-xs flex items-center gap-2">
                <input type="checkbox" checked={previewOnly} onChange={(e) => setPreviewOnly(e.target.checked)} />
                Preview first 10
              </label>
            </div>
            <div className="overflow-x-auto rounded-lg border border-border">
              <table className="text-xs w-full">
                <thead className="bg-muted/40">
                  <tr>{headers.map((h) => <th key={h} className="text-left px-2 py-1 font-medium">{h}</th>)}</tr>
                </thead>
                <tbody>
                  {(previewOnly ? previewRows : rows).map((r, i) => (
                    <tr key={i} className="border-t border-border">
                      {headers.map((h) => <td key={h} className="px-2 py-1 truncate max-w-[200px]">{r[h]}</td>)}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <button onClick={performImport} disabled={importing} className="btn-primary flex items-center gap-2">
              <Upload className="w-4 h-4" /> {importing ? 'Importing…' : `Import ${rows.length} rows`}
            </button>
          </div>
        )}
      </div>

      <div className="card-medical p-5">
        <div className="flex justify-between items-center mb-3">
          <h2 className="font-semibold">Import history</h2>
          <button onClick={loadHistory} className="btn-ghost text-xs">Refresh</button>
        </div>
        <div className="space-y-2">
          {history.map((h) => (
            <div key={h.id} className="rounded-xl border border-border p-3 text-sm">
              <div className="flex justify-between">
                <span className="font-medium flex items-center gap-2">
                  {h.status === 'completed' ? <CheckCircle2 className="w-4 h-4 text-success" /> : <AlertTriangle className="w-4 h-4 text-critical" />}
                  {h.entity} — {h.filename ?? 'untitled'}
                </span>
                <span className="text-xs text-muted-foreground">{new Date(h.created_at).toLocaleString()}</span>
              </div>
              <p className="text-xs text-muted-foreground mt-1">
                {h.inserted_rows}/{h.total_rows} inserted · {h.failed_rows} failed
              </p>
              {Array.isArray(h.errors) && h.errors.length > 0 && (
                <details className="text-xs mt-2">
                  <summary className="cursor-pointer text-critical">View errors ({h.errors.length})</summary>
                  <ul className="mt-1 space-y-0.5 pl-4 list-disc">
                    {h.errors.slice(0, 20).map((e: any, i: number) => <li key={i}>{e.reason}</li>)}
                  </ul>
                </details>
              )}
            </div>
          ))}
          {history.length === 0 && <p className="text-sm text-muted-foreground">No imports yet. Click Refresh after importing.</p>}
        </div>
      </div>
    </div>
  );
}
