import { useEffect, useMemo, useState } from 'react';
import { BarChart3, CheckCircle2, Download, FileSpreadsheet, FileText, Loader2, Plus, RefreshCw, Settings2, ShieldCheck, TriangleAlert } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { cn } from '@/lib/utils';
import {
  createFacility, downloadRunManifestCsv, downloadRunWorkbook, generateRun, getRunItems, listDefinitions, listFacilities, listFacilityConfigs, setReportEnabled,
  type FacilityReportConfig, type HealthcareFacility, type ReportDefinition, type ReportRun, type ReportRunItem,
} from '@/lib/reportsCenter';

const facilityTypes = [
  ['chps_compound', 'CHPS Compound'], ['health_centre', 'Health Centre'], ['district_hospital', 'District Hospital'],
  ['regional_hospital', 'Regional Hospital'], ['teaching_hospital', 'Teaching Hospital'], ['hiv_clinic', 'HIV Clinic'],
  ['maternity_home', 'Maternity Home'], ['specialist_clinic', 'Specialist Clinic'], ['other', 'Other'],
];

function previousMonth() {
  const date = new Date(); date.setUTCDate(1); date.setUTCMonth(date.getUTCMonth() - 1);
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
}

export default function ReportsCenter() {
  const { user } = useAuth();
  const [facilities, setFacilities] = useState<HealthcareFacility[]>([]);
  const [definitions, setDefinitions] = useState<ReportDefinition[]>([]);
  const [configs, setConfigs] = useState<FacilityReportConfig[]>([]);
  const [selectedFacilityId, setSelectedFacilityId] = useState('');
  const [period, setPeriod] = useState(previousMonth());
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [run, setRun] = useState<ReportRun | null>(null);
  const [runItems, setRunItems] = useState<ReportRunItem[]>([]);
  const [showSetup, setShowSetup] = useState(false);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('all');
  const [facilityForm, setFacilityForm] = useState({ name: '', facility_code: '', facility_type: 'district_hospital', district: '', region: '', dhims2_uid: '' });

  const selectedFacility = facilities.find((facility) => facility.id === selectedFacilityId) ?? null;
  const enabledConfigs = configs.filter((config) => config.is_enabled && config.report?.frequency === 'monthly');
  const categories = useMemo(() => Array.from(new Set(definitions.map((definition) => definition.category?.name).filter(Boolean))) as string[], [definitions]);
  const visibleConfigs = useMemo(() => configs.filter((config) => {
    const report = config.report; if (!report) return false;
    return report.report_name.toLowerCase().includes(search.toLowerCase()) && (category === 'all' || report.category?.name === category);
  }), [configs, search, category]);

  async function load() {
    setLoading(true);
    try {
      const [facilityRows, definitionRows] = await Promise.all([listFacilities(), listDefinitions()]);
      setFacilities(facilityRows); setDefinitions(definitionRows);
      const preferred = selectedFacilityId || facilityRows[0]?.id || '';
      setSelectedFacilityId(preferred);
      if (preferred) setConfigs(await listFacilityConfigs(preferred)); else setConfigs([]);
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Unable to load Reports Center.'); }
    finally { setLoading(false); }
  }

  useEffect(() => { void load(); }, []);
  useEffect(() => { if (!selectedFacilityId) return; listFacilityConfigs(selectedFacilityId).then(setConfigs).catch((error) => toast.error(error instanceof Error ? error.message : 'Unable to load facility reports.')); }, [selectedFacilityId]);

  async function toggle(config: FacilityReportConfig) {
    try { await setReportEnabled(selectedFacilityId, config.report_id, !config.is_enabled); setConfigs((current) => current.map((entry) => entry.id === config.id ? { ...entry, is_enabled: !entry.is_enabled } : entry)); }
    catch (error) { toast.error(error instanceof Error ? error.message : 'Unable to update report configuration.'); }
  }

  async function createNewFacility() {
    if (!facilityForm.name.trim()) { toast.error('Facility name is required.'); return; }
    try {
      const facility = await createFacility({ ...facilityForm, facility_code: facilityForm.facility_code || null, district: facilityForm.district || null, region: facilityForm.region || null, dhims2_uid: facilityForm.dhims2_uid || null });
      setFacilities((current) => [...current, facility]); setSelectedFacilityId(facility.id); setShowSetup(false); setFacilityForm({ name: '', facility_code: '', facility_type: 'district_hospital', district: '', region: '', dhims2_uid: '' });
      toast.success('Facility created and default report configuration seeded.');
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Unable to create facility.'); }
  }

  async function generateAll() {
    if (!selectedFacility) { toast.error('Select a facility first.'); return; }
    setGenerating(true); setRun(null); setRunItems([]);
    try {
      const nextRun = await generateRun(selectedFacility.id, period, configs); setRun(nextRun); setRunItems(await getRunItems(nextRun.id)); toast.success('Reports Center generation completed. Review warnings before submission.');
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Report generation failed.'); }
    finally { setGenerating(false); }
  }

  async function refreshRun() { if (run) setRunItems(await getRunItems(run.id)); }

  if (loading) return <div className="flex min-h-[50vh] items-center justify-center"><Loader2 className="h-6 w-6 animate-spin text-primary" /></div>;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <div className="flex items-center gap-2 text-sm text-primary font-medium"><ShieldCheck className="h-4 w-4" /> Ministry Reporting & Compliance</div>
          <h1 className="mt-1 text-2xl font-heading font-bold">Reports Center</h1>
          <p className="text-muted-foreground">Facility-configured public-health reporting with traceable generation and submission readiness.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          {user?.role === 'admin' && <button className="btn-secondary inline-flex items-center gap-2" onClick={() => setShowSetup((value) => !value)}><Plus className="h-4 w-4" /> Facility</button>}
          <button className="btn-secondary inline-flex items-center gap-2" onClick={() => void load()}><RefreshCw className="h-4 w-4" /> Refresh</button>
        </div>
      </div>

      {showSetup && user?.role === 'admin' && <section className="card-medical p-5 space-y-4">
        <div><h2 className="font-semibold">Add healthcare facility</h2><p className="text-sm text-muted-foreground">Create the facility boundary first; its report catalogue is seeded from facility type.</p></div>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <input className="input" placeholder="Facility name" value={facilityForm.name} onChange={(e) => setFacilityForm({ ...facilityForm, name: e.target.value })} />
          <input className="input" placeholder="Facility code" value={facilityForm.facility_code} onChange={(e) => setFacilityForm({ ...facilityForm, facility_code: e.target.value })} />
          <select className="input" value={facilityForm.facility_type} onChange={(e) => setFacilityForm({ ...facilityForm, facility_type: e.target.value })}>{facilityTypes.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select>
          <input className="input" placeholder="District" value={facilityForm.district} onChange={(e) => setFacilityForm({ ...facilityForm, district: e.target.value })} />
          <input className="input" placeholder="Region" value={facilityForm.region} onChange={(e) => setFacilityForm({ ...facilityForm, region: e.target.value })} />
          <input className="input" placeholder="DHIMS2 UID (when validated)" value={facilityForm.dhims2_uid} onChange={(e) => setFacilityForm({ ...facilityForm, dhims2_uid: e.target.value })} />
        </div>
        <button className="btn-primary" onClick={() => void createNewFacility()}>Create facility</button>
      </section>}

      {!facilities.length ? <section className="card-medical p-8 text-center space-y-3"><Settings2 className="mx-auto h-8 w-8 text-primary" /><h2 className="text-lg font-semibold">Facility setup required</h2><p className="text-sm text-muted-foreground">Reports are facility-scoped. An administrator must create the first facility before reports can be activated or generated.</p>{user?.role === 'admin' && <button className="btn-primary inline-flex items-center gap-2" onClick={() => setShowSetup(true)}><Plus className="h-4 w-4" /> Create facility</button>}</section> : <>
        <section className="grid gap-4 md:grid-cols-4">
          <div className="card-medical p-5"><p className="text-xs uppercase tracking-wide text-muted-foreground">Facility</p><select className="mt-2 w-full bg-transparent font-semibold outline-none" value={selectedFacilityId} onChange={(e) => setSelectedFacilityId(e.target.value)}>{facilities.map((facility) => <option key={facility.id} value={facility.id}>{facility.name}</option>)}</select><p className="mt-1 text-xs text-muted-foreground">{selectedFacility?.facility_type.replaceAll('_', ' ')}</p></div>
          <div className="card-medical p-5"><p className="text-xs uppercase tracking-wide text-muted-foreground">Activated monthly</p><p className="mt-2 text-2xl font-bold">{enabledConfigs.length}</p><p className="text-xs text-muted-foreground">of {definitions.filter((definition) => definition.frequency === 'monthly').length} monthly definitions</p></div>
          <div className="card-medical p-5"><p className="text-xs uppercase tracking-wide text-muted-foreground">Catalogue</p><p className="mt-2 text-2xl font-bold">{definitions.length}</p><p className="text-xs text-muted-foreground">seeded report definitions</p></div>
          <div className="card-medical p-5"><p className="text-xs uppercase tracking-wide text-muted-foreground">Period</p><input className="mt-2 w-full bg-transparent text-lg font-semibold outline-none" type="month" value={period} onChange={(e) => setPeriod(e.target.value)} /></div>
        </section>

        <section className="card-medical p-5">
          <div className="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
            <div><h2 className="text-lg font-semibold">Bulk monthly generation</h2><p className="text-sm text-muted-foreground">Generates the activated reports into one reviewable workbook plus a manifest. Unsupported/unmapped definitions are explicitly warned, never fabricated.</p></div>
            <button disabled={generating || !enabledConfigs.length} className="btn-primary inline-flex items-center justify-center gap-2 disabled:opacity-50" onClick={() => void generateAll()}>{generating ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileSpreadsheet className="h-4 w-4" />}{generating ? 'Generating…' : 'Generate All Monthly Reports'}</button>
          </div>
          {run && <div className="mt-5 rounded-2xl border border-border p-4 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-3"><div><p className="font-semibold">Run {run.period_start.slice(0, 7)}</p><p className="text-xs text-muted-foreground">{run.success_count} complete · {run.warning_count} warning · {run.failed_count} failed</p></div><div className="flex gap-2"><button className="btn-secondary inline-flex items-center gap-2" onClick={() => void refreshRun()}><RefreshCw className="h-4 w-4" /> Refresh</button><button className="btn-secondary inline-flex items-center gap-2" onClick={() => void downloadRunWorkbook(run, runItems, selectedFacility!)}><Download className="h-4 w-4" /> Excel</button><button className="btn-secondary inline-flex items-center gap-2" onClick={() => downloadRunManifestCsv(run, runItems, selectedFacility!)}><FileText className="h-4 w-4" /> Manifest CSV</button></div></div>
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">{runItems.map((item) => <div key={item.id} className="rounded-xl border border-border p-3"><div className="flex items-start gap-2">{item.status === 'completed' ? <CheckCircle2 className="mt-0.5 h-4 w-4 text-success" /> : item.status === 'warning' ? <TriangleAlert className="mt-0.5 h-4 w-4 text-warning" /> : <TriangleAlert className="mt-0.5 h-4 w-4 text-critical" />}<div className="min-w-0"><p className="text-sm font-medium truncate">{item.file_name ?? item.report_id}</p><p className="text-xs text-muted-foreground">{item.data_snapshot.total} source records · {item.status}</p>{item.validation_messages[0] && <p className="mt-1 text-xs text-warning line-clamp-2">{item.validation_messages[0]}</p>}</div></div></div>)}</div>
          </div>}
        </section>

        <section className="card-medical p-5">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between"><div><h2 className="text-lg font-semibold">Activated report library</h2><p className="text-sm text-muted-foreground">Only reports activated for the selected facility are eligible for bulk generation.</p></div><div className="flex flex-col gap-2 sm:flex-row"><input className="input" placeholder="Search reports" value={search} onChange={(e) => setSearch(e.target.value)} /><select className="input" value={category} onChange={(e) => setCategory(e.target.value)}><option value="all">All categories</option>{categories.map((item) => <option key={item} value={item}>{item}</option>)}</select></div></div>
          <div className="mt-5 grid gap-3">{visibleConfigs.map((config) => { const report = config.report!; return <div key={config.id} className={cn('flex flex-col gap-3 rounded-2xl border p-4 md:flex-row md:items-center md:justify-between', config.is_enabled ? 'border-primary/30 bg-primary/5' : 'border-border')}><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><span className="text-xs font-mono text-muted-foreground">{report.report_code}</span><span className="rounded-full bg-muted px-2 py-0.5 text-[10px] uppercase tracking-wide">{report.frequency}</span>{report.implementation_status === 'seeded' && <span className="rounded-full bg-warning/10 px-2 py-0.5 text-[10px] text-warning">Validation pending</span>}</div><p className="mt-1 font-medium">{report.report_name}</p><p className="text-xs text-muted-foreground">{report.description}</p></div><button className={cn('inline-flex items-center justify-center rounded-xl px-3 py-2 text-sm font-medium transition-colors', config.is_enabled ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground')} onClick={() => void toggle(config)}>{config.is_enabled ? 'Activated' : 'Activate'}</button></div>; })}</div>
        </section>

        <section className="card-medical p-5"><div className="flex items-center gap-3"><BarChart3 className="h-5 w-5 text-primary" /><div><h2 className="text-lg font-semibold">Compliance dashboard foundation</h2><p className="text-sm text-muted-foreground">Submission records are stored per facility, report and period so completeness/timeliness rates can be added without changing the generation model.</p></div></div><div className="mt-4 grid gap-3 sm:grid-cols-3"><div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Generation completeness</p><p className="mt-1 text-xl font-bold">{run ? `${run.total_reports ? Math.round(((run.success_count + run.warning_count) / run.total_reports) * 100) : 0}%` : '—'}</p></div><div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Timeliness</p><p className="mt-1 text-xl font-bold">Submission tracking ready</p></div><div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">DHIMS2 integration</p><p className="mt-1 text-xl font-bold">Phase 2</p></div></div></section>
      </>}
    </div>
  );
}
