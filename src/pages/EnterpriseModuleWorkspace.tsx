import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { AlertCircle, Plus, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { getModuleContract } from '@/lib/nextGenModuleManifest';

type Field = { key: string; label: string; required?: boolean; type?: 'text'|'date'|'datetime-local'|'textarea'|'select'; options?: string[]; json?: boolean };

const MODULES: Record<string, { title: string; description: string; fields: Field[]; collection: string }> = {
  'hr-payroll': { title: 'HR & Payroll', description: 'Employee records and workforce administration.', collection: 'employees', fields: [
    {key:'employee_number',label:'Employee number',required:true},{key:'full_name',label:'Full name',required:true},{key:'department_code',label:'Department'},{key:'job_title',label:'Job title'},{key:'employment_status',label:'Status',type:'select',options:['active','leave','suspended','terminated']},{key:'hire_date',label:'Hire date',type:'date'}
  ]},
  'icu-critical-care': { title: 'ICU & Critical Care', description: 'Critical-care stays, acuity and escalation-ready observations.', collection: 'stays', fields: [
    {key:'patient_id',label:'Patient ID',required:true},{key:'encounter_id',label:'Encounter ID'},{key:'bed_reference',label:'ICU bed'},{key:'acuity',label:'Acuity',type:'select',options:['high','critical','medium']},{key:'status',label:'Status',type:'select',options:['active','transferred','discharged']}
  ]},
  'mental-health': { title: 'Mental Health', description: 'Assessment, risk and care-plan documentation.', collection: 'assessments', fields: [
    {key:'patient_id',label:'Patient ID',required:true},{key:'encounter_id',label:'Encounter ID'},{key:'risk_level',label:'Risk level',type:'select',options:['unknown','low','moderate','high','critical']},{key:'assessment',label:'Assessment',type:'textarea',json:true},{key:'care_plan',label:'Care plan',type:'textarea',json:true}
  ]},
  'social-work': { title: 'Social Work', description: 'Psychosocial assessment, safeguarding and case management.', collection: 'cases', fields: [
    {key:'patient_id',label:'Patient ID',required:true},{key:'encounter_id',label:'Encounter ID'},{key:'case_type',label:'Case type',required:true},{key:'safeguarding_level',label:'Safeguarding',type:'select',options:['none','low','moderate','high','critical']},{key:'assessment',label:'Assessment',type:'textarea',json:true}
  ]},
  'quality-compliance': { title: 'Quality & Compliance', description: 'Incident reporting and corrective-action governance.', collection: 'incidents', fields: [
    {key:'incident_code',label:'Incident code',required:true},{key:'category',label:'Category',required:true},{key:'severity',label:'Severity',type:'select',options:['minor','moderate','major','critical']},{key:'patient_id',label:'Patient ID'},{key:'description',label:'Description',required:true,type:'textarea'}
  ]},
  'infection-control': { title: 'Infection Prevention & Control', description: 'Exposure events, surveillance and corrective actions.', collection: 'events', fields: [
    {key:'event_type',label:'Event type',required:true},{key:'organism',label:'Organism'},{key:'location',label:'Location'},{key:'risk_level',label:'Risk level',type:'select',options:['low','moderate','high','critical']},{key:'patient_id',label:'Patient ID'}
  ]},
  'mortuary': { title: 'Mortuary', description: 'Case intake, custody, identity verification and release.', collection: 'cases', fields: [
    {key:'case_number',label:'Case number',required:true},{key:'patient_id',label:'Patient ID'},{key:'storage_location',label:'Storage location'},{key:'custody_status',label:'Custody status',type:'select',options:['received','identified','released','transferred']}
  ]},
  'ambulance': { title: 'Ambulance & Transport', description: 'Dispatch, trip lifecycle and clinical handover.', collection: 'trips', fields: [
    {key:'ambulance_reference',label:'Ambulance',required:true},{key:'patient_id',label:'Patient ID'},{key:'pickup_location',label:'Pickup location',required:true},{key:'destination',label:'Destination',required:true}
  ]},
  'research-portal': { title: 'Research Portal', description: 'Governed projects, ethics references and retention.', collection: 'projects', fields: [
    {key:'project_code',label:'Project code',required:true},{key:'title',label:'Project title',required:true},{key:'protocol_version',label:'Protocol version'},{key:'ethics_reference',label:'Ethics reference'},{key:'data_purpose',label:'Data purpose',required:true},{key:'retention_until',label:'Retention until',type:'date'}
  ]},
  'external-audit': { title: 'External Audit', description: 'Controlled audit engagements and evidence requests.', collection: 'engagements', fields: [
    {key:'audit_type',label:'Audit type',required:true},{key:'starts_on',label:'Start date',type:'date'},{key:'ends_on',label:'End date',type:'date'}
  ]},
  'genomics': { title: 'Genomics', description: 'Genomic orders, specimen provenance, consent and findings.', collection: 'orders', fields: [
    {key:'patient_id',label:'Patient ID',required:true},{key:'encounter_id',label:'Encounter ID'},{key:'test_code',label:'Test code',required:true},{key:'specimen_reference',label:'Specimen reference'},{key:'consent_reference',label:'Consent reference',required:true}
  ]},
};

function displayValue(value: unknown) {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

export default function EnterpriseModuleWorkspace() {
  const { moduleId = '' } = useParams();
  const config = MODULES[moduleId];
  const contract = getModuleContract(moduleId);
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [data, setData] = useState<Record<string, unknown[]>>({});
  const [form, setForm] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const loadFacility = useCallback(async () => {
    const { data: rows, error: facilityError } = await supabase.from('user_active_facilities').select('facility_id').eq('user_id', (await supabase.auth.getUser()).data.user?.id ?? '').limit(1);
    if (facilityError) throw facilityError;
    setFacilityId(rows?.[0]?.facility_id ?? null);
    return rows?.[0]?.facility_id ?? null;
  }, []);

  const load = useCallback(async () => {
    if (!config) return;
    setLoading(true); setError(null); setNotice(null);
    try {
      const id = facilityId ?? await loadFacility();
      if (!id) throw new Error('An active facility context is required before opening this module.');
      const { data: workspace, error: workspaceError } = await supabase.rpc('hms_get_enterprise_workspace', { _facility_id: id, _module_id: moduleId });
      if (workspaceError) throw workspaceError;
      setData((workspace ?? {}) as Record<string, unknown[]>);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unable to load enterprise workspace.');
    } finally { setLoading(false); }
  }, [config, facilityId, loadFacility, moduleId]);

  useEffect(() => { void load(); }, [load]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!facilityId || !config) return;
    setSaving(true); setError(null); setNotice(null);
    try {
      const payload: Record<string, unknown> = {};
      for (const field of config.fields) {
        const value = form[field.key]?.trim() ?? '';
        if (field.required && !value) throw new Error(field.label + ' is required.');
        if (!value) continue;
        if (field.json) {
          try { payload[field.key] = JSON.parse(value); } catch { payload[field.key] = { note: value }; }
        } else payload[field.key] = value;
      }
      const { error: saveError } = await supabase.rpc('hms_create_enterprise_record', { _facility_id: facilityId, _module_id: moduleId, _payload: payload });
      if (saveError) throw saveError;
      setForm({}); setNotice('Record created and audited successfully.'); await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unable to create record.');
    } finally { setSaving(false); }
  };

  const rows = useMemo(() => Array.isArray(data[config?.collection ?? '']) ? data[config?.collection ?? ''] as Record<string, unknown>[] : [], [config?.collection, data]);

  if (!config) return <main className="p-6"><div className="rounded-xl border p-6"><h1 className="text-xl font-semibold">Module not available</h1><p className="mt-2 text-sm text-muted-foreground">This enterprise module has no operational workspace contract.</p></div></main>;

  return <main className="mx-auto w-full max-w-7xl space-y-6 p-4 md:p-6" aria-labelledby="enterprise-title">
    <header className="rounded-2xl border bg-card p-6 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-4"><div><p className="text-sm font-medium text-primary">Enterprise Operations</p><h1 id="enterprise-title" className="mt-1 text-2xl font-semibold">{config.title}</h1><p className="mt-2 max-w-3xl text-sm text-muted-foreground">{config.description}</p></div><button type="button" onClick={() => void load()} className="inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-sm" disabled={loading}><RefreshCw className="h-4 w-4" /> Refresh</button></div>
      <div className="mt-4 flex flex-wrap gap-2 text-xs text-muted-foreground"><span className="rounded-full border px-3 py-1">{moduleId}</span><span className="rounded-full border px-3 py-1">{contract?.requiredCapabilities.length ?? 0} capabilities</span><span className="rounded-full border px-3 py-1">{rows.length} records</span>{facilityId && <span className="rounded-full border px-3 py-1">Facility context active</span>}</div>
    </header>
    {error && <div role="alert" className="rounded-xl border border-destructive/40 bg-destructive/5 p-4 text-sm"><AlertCircle className="mr-2 inline h-4 w-4" />{error}</div>}
    {notice && <div role="status" className="rounded-xl border bg-muted p-4 text-sm">{notice}</div>}
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_360px]">
      <section className="rounded-2xl border bg-card p-5 shadow-sm" aria-labelledby="records-title"><div className="flex items-center justify-between gap-3"><h2 id="records-title" className="text-lg font-semibold">Operational records</h2><span className="text-xs text-muted-foreground">{rows.length} loaded</span></div>{loading ? <p className="py-10 text-sm text-muted-foreground">Loading workspace…</p> : rows.length === 0 ? <p className="py-10 text-sm text-muted-foreground">No records found for the active facility.</p> : <div className="mt-4 overflow-auto rounded-xl border"><table className="w-full min-w-[720px] text-sm"><thead className="bg-muted/50 text-left"><tr>{Object.keys(rows[0]).slice(0,10).map(key => <th key={key} className="px-3 py-2 font-medium">{key.replaceAll('_',' ')}</th>)}</tr></thead><tbody>{rows.map((row,index) => <tr key={String(row.id ?? index)} className="border-t align-top">{Object.keys(rows[0]).slice(0,10).map(key => <td key={key} className="max-w-[260px] px-3 py-2">{displayValue(row[key])}</td>)}</tr>)}</tbody></table></div>}</section>
      <aside className="rounded-2xl border bg-card p-5 shadow-sm" aria-labelledby="add-record-title"><div className="flex items-center gap-2"><Plus className="h-4 w-4" /><h2 id="add-record-title" className="text-lg font-semibold">Add record</h2></div><p className="mt-1 text-xs text-muted-foreground">Server-side module and role authorization is checked before the write.</p><form onSubmit={submit} className="mt-4 space-y-3">{config.fields.map(field => <div key={field.key}><label htmlFor={'enterprise-'+field.key} className="mb-1 block text-sm font-medium">{field.label}{field.required ? ' *' : ''}</label>{field.type === 'textarea' ? <textarea id={'enterprise-'+field.key} autoComplete="off" rows={4} className="w-full rounded-lg border bg-background px-3 py-2 text-sm" value={form[field.key] ?? ''} onChange={e => setForm(v => ({...v,[field.key]:e.target.value}))} /> : field.type === 'select' ? <select id={'enterprise-'+field.key} className="w-full rounded-lg border bg-background px-3 py-2 text-sm" value={form[field.key] ?? ''} onChange={e => setForm(v => ({...v,[field.key]:e.target.value}))}><option value="">Select…</option>{field.options?.map(option => <option key={option} value={option}>{option}</option>)}</select> : <input id={'enterprise-'+field.key} type={field.type ?? 'text'} autoComplete={field.key.includes('id') ? 'off' : 'on'} className="w-full rounded-lg border bg-background px-3 py-2 text-sm" value={form[field.key] ?? ''} onChange={e => setForm(v => ({...v,[field.key]:e.target.value}))} />}</div>)}<button type="submit" disabled={saving || loading || !facilityId} className="w-full rounded-lg bg-primary px-3 py-2 text-sm font-medium text-primary-foreground disabled:opacity-50">{saving ? 'Saving…' : 'Create record'}</button></form></aside>
    </div>
  </main>;
}
