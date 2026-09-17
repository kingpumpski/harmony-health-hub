import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { BookOpen, DownloadCloud, Database, ShieldCheck, Layers, UploadCloud } from 'lucide-react';
import { icdReferences, downloadCsvTemplate, treatmentGuidelines } from '@/lib/clinicalLibrary';

const migrationHeaders = {
  stg_diagnoses: ['code', 'display_name', 'description', 'category', 'synonyms', 'source_reference', 'is_active'],
  service_tariffs: ['service_code', 'service_name', 'department', 'unit', 'amount', 'currency', 'effective_from', 'effective_to', 'active', 'metadata'],
  legacy_clinical_records: ['source_system', 'source_version', 'source_patient_key', 'source_record_id', 'record_type', 'occurred_at', 'author_name', 'department', 'encounter_reference', 'clinical_summary', 'raw_record'],
};

function downloadMigrationTemplate(type: keyof typeof migrationHeaders) {
  const headers = migrationHeaders[type];
  const sample = headers.map((field) => field === 'source_system' ? 'Legacy system' : `${field}_example`);
  const csv = `${headers.join(',')}\n${sample.join(',')}`;
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8;' }));
  const link = document.createElement('a'); link.href = url; link.download = `${type}-migration-template.csv`; link.click(); URL.revokeObjectURL(url);
}

export default function SystemLibrary() {
  const { user } = useAuth();
  const isAdmin = user?.role === 'admin';
  const specialties = useMemo(() => ['Patient / Client Database','Staff and Practitioners','Tariff and Service Catalog','Insurance Provider List','Medication Inventory','ICD-10 / ICD-11 Clinical References','Ghana Standard Treatment Guidelines','Legacy Clinical Record Migration','Service / Tariff Master Data'], []);
  if (!user) return null;
  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold">System Administration Library</h1><p className="text-muted-foreground">Admin-only master data, clinical references and migration templates.</p></div><div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3"><Database className="w-5 h-5 text-primary" /><span className="text-sm text-muted-foreground">Central reference data for clinical, billing, pharmacy and migration workflows.</span></div></div>
    {!isAdmin && <div className="rounded-3xl border border-warning/30 bg-warning/10 p-5 text-warning">Only admin users may modify system-level clinical libraries and migration templates.</div>}
    <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
      <div className="space-y-6">
        <div className="card-medical p-6"><div className="flex items-center gap-3 mb-4"><ShieldCheck className="w-5 h-5 text-success" /><p className="text-sm text-muted-foreground">Standard templates for controlled reference-data imports.</p></div><div className="grid gap-3 sm:grid-cols-2">{(['patients','staff','tariff','insurance','medication','guidelines'] as const).map((template) => <button key={template} disabled={!isAdmin} onClick={() => downloadCsvTemplate(template)} className="btn-secondary inline-flex items-center justify-between gap-2"><span>Download {template.replace(/\b\w/g, (c) => c.toUpperCase())} Template</span><DownloadCloud className="w-4 h-4" /></button>)}</div></div>
        <div className="card-medical p-6"><div className="flex items-center gap-3 mb-4"><UploadCloud className="w-5 h-5 text-primary" /><div><p className="font-semibold">Enterprise migration templates</p><p className="text-xs text-muted-foreground">These templates feed the governed Data Import & Migration Workspace.</p></div></div><div className="grid gap-3 sm:grid-cols-2">{(Object.keys(migrationHeaders) as Array<keyof typeof migrationHeaders>).map((template) => <button key={template} disabled={!isAdmin} onClick={() => downloadMigrationTemplate(template)} className="btn-secondary inline-flex items-center justify-between gap-2"><span>Download {template.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())}</span><DownloadCloud className="w-4 h-4" /></button>)}</div><p className="text-xs text-muted-foreground mt-4">Legacy clinical records are staged with source provenance and require patient matching and reconciliation before promotion into native encounters, diagnoses, prescriptions, laboratory results or other clinical modules.</p></div>
        <div className="card-medical p-6"><div className="flex items-center gap-3 mb-4"><BookOpen className="w-5 h-5 text-primary" /><p className="text-sm text-muted-foreground">Reference snippets remain available for orientation; the migration workspace is the controlled path for facility-provided current source datasets.</p></div><div className="space-y-3"><p className="text-sm font-semibold">ICD Reference Samples</p>{icdReferences.map((item) => <div key={item.code} className="rounded-3xl border border-border p-4 bg-background/80"><p className="font-medium">{item.code} • {item.description}</p><p className="text-sm text-muted-foreground">{item.category}</p><p className="text-sm mt-2">{item.guideline}</p></div>)}<p className="text-sm font-semibold pt-2">Standard Treatment Guidelines</p>{treatmentGuidelines.map((item) => <div key={item.condition} className="rounded-3xl border border-border p-4 bg-background/80"><p className="font-medium">{item.condition}</p><p className="text-sm text-muted-foreground">{item.summary}</p><p className="text-sm mt-2 font-semibold">Action:</p><p className="text-sm">{item.recommendedAction}</p></div>)}</div></div>
      </div>
      <div className="card-medical p-6"><div className="flex items-center justify-between mb-4"><div><p className="text-sm font-medium">System Data Areas</p><p className="text-xs text-muted-foreground">Review or update only when authorized.</p></div><Layers className="w-5 h-5 text-secondary" /></div><div className="space-y-3">{specialties.map((item) => <div key={item} className="rounded-3xl border border-border p-4"><p className="font-medium">{item}</p></div>)}</div></div>
    </div>
  </div>;
}
