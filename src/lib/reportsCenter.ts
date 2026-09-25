import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { supabase } from '@/integrations/supabase/client';
import { reportsDb } from '@/lib/reportsDb';
import * as XLSX from 'xlsx';

export type ReportFrequency = 'weekly' | 'monthly' | 'quarterly' | 'annual';
export type ReportStatus = 'queued' | 'processing' | 'completed' | 'warning' | 'failed';
export interface ReportCategory { id: string; name: string; display_order: number; }
export interface ReportDefinition { id: string; report_code: string; report_name: string; category_id: string | null; description: string | null; frequency: ReportFrequency; parameters: string[]; default_parameters: Record<string, unknown>; extractor_key: string; supported_formats: string[]; submission_deadline_day: number; is_active: boolean; implementation_status: 'seeded' | 'mapped' | 'validated' | 'retired'; category?: ReportCategory | null; }
export interface HealthcareFacility { id: string; name: string; facility_code: string | null; facility_type: string; district: string | null; region: string | null; dhims2_uid: string | null; is_active: boolean; }
export interface FacilityReportConfig { id: string; facility_id: string; report_id: string; is_enabled: boolean; submission_deadline_day: number | null; custom_parameters: Record<string, unknown>; report?: ReportDefinition; }
export interface ReportSnapshot { total: number; by_dimension: Array<{ dimension: string; value: string; count: number }>; source: string; warning?: string; error?: string; }
export interface ReportRunItem { id: string; run_id: string; report_id: string; status: ReportStatus; output_format: 'xlsx' | 'csv' | 'pdf'; file_name: string | null; data_snapshot: ReportSnapshot; validation_messages: string[]; error_message: string | null; }
export interface ReportRun { id: string; facility_id: string; period_start: string; period_end: string; frequency: ReportFrequency; status: string; total_reports: number; success_count: number; warning_count: number; failed_count: number; created_at: string; completed_at: string | null; }
export interface FacilityNotificationConfig {
  facility_id: string;
  environment: 'sandbox' | 'test' | 'production';
  enabled: boolean;
  default_locale: string;
  default_timezone: string;
  quiet_hours_start: string;
  quiet_hours_end: string;
  enabled_channels: Record<string, boolean>;
  rollout_percent: number;
  kill_switch: boolean;
  onboarding_status: 'not_started' | 'in_progress' | 'sandbox_ready' | 'verification_pending' | 'production_ready' | 'suspended';
  branding: Record<string, unknown>;
  provider_defaults: Record<string, unknown>;
  delivery_policy: Record<string, unknown>;
  webhook_policy: Record<string, unknown>;
  compliance_policy: Record<string, unknown>;
  operational_contacts: Record<string, unknown>;
  deployment_secret_namespace: string | null;
  production_approved_at: string | null;
  production_approved_by: string | null;
}
export interface NotificationProviderSecretRequirement {
  id: string;
  provider: string;
  channel: 'email' | 'sms' | 'push' | 'whatsapp' | 'voice';
  secret_name: string;
  environment: 'all' | 'sandbox' | 'test' | 'production';
  required: boolean;
  description: string;
  secret_reference_example: string | null;
}
export interface ReportSubmission { id: string; report_id: string; facility_id: string; period_start: string; period_end: string; due_date: string; status: 'pending' | 'submitted' | 'overdue' | 'accepted' | 'rejected'; submitted_at: string | null; submitted_by: string | null; submission_reference: string | null; }

const SOURCE_TABLES: Record<string, string> = { opd_morbidity: 'encounters + diagnoses', opd_attendance: 'appointments', laboratory: 'lab_orders + lab_results', inpatient_days: 'admissions / inpatient module', surgeries: 'procedure/theatre module', maternity: 'maternity module' };

function monthBounds(period: string) {
  const match = /^(\d{4})-(\d{2})$/.exec(period);
  if (!match) throw new Error('Report period must use the YYYY-MM format.');
  const year = Number(match[1]);
  const month = Number(match[2]);
  if (month < 1 || month > 12) throw new Error('Report period month must be between 01 and 12.');
  const start = new Date(Date.UTC(year, month - 1, 1));
  if (start.getUTCFullYear() !== year || start.getUTCMonth() !== month - 1) throw new Error('Report period contains an invalid calendar year.');
  const end = new Date(Date.UTC(year, month, 0, 23, 59, 59, 999));
  return { start: start.toISOString(), end: end.toISOString() };
}

async function countTable(table: string, dateColumn: string, start: string, end: string) {
  const result = await reportsDb.from(table).select('id', { count: 'exact', head: true }).gte(dateColumn, start).lte(dateColumn, end);
  if (result.error) throw new Error(result.error.message);
  return result.count ?? 0;
}

async function extractSnapshot(report: ReportDefinition, period: string): Promise<ReportSnapshot> {
  const { start, end } = monthBounds(period);
  try {
    switch (report.extractor_key) {
      case 'opd_morbidity': {
        const total = await countTable('diagnoses', 'created_at', start, end);
        return { total, by_dimension: [{ dimension: 'diagnoses recorded', value: 'all', count: total }], source: 'diagnoses', warning: 'Facility-level attribution is pending because legacy clinical rows are not yet facility-scoped.' };
      }
      case 'opd_attendance': {
        const total = await countTable('appointments', 'scheduled_at', start, end);
        return { total, by_dimension: [{ dimension: 'appointments', value: 'all', count: total }], source: 'appointments', warning: 'Attendance classification will be completed when the OPD attendance data dictionary is mapped.' };
      }
      case 'laboratory': {
        const orders = await countTable('lab_orders', 'created_at', start, end);
        const results = await countTable('lab_results', 'entered_at', start, end);
        return { total: orders, by_dimension: [{ dimension: 'lab orders', value: 'all', count: orders }, { dimension: 'results entered', value: 'all', count: results }], source: 'lab_orders + lab_results' };
      }
      default:
        return { total: 0, by_dimension: [], source: SOURCE_TABLES[report.extractor_key] ?? 'data dictionary mapping', warning: 'No validated source adapter is registered yet. This report remains seeded/configurable but is not presented as DHIMS2-validated output.' };
    }
  } catch (error) {
    return { total: 0, by_dimension: [], source: SOURCE_TABLES[report.extractor_key] ?? 'unknown', error: error instanceof Error ? error.message : 'Unable to read source data.' };
  }
}

export async function listFacilities(): Promise<HealthcareFacility[]> {
  const { data, error } = await getOperationalWorkspace('facilities', 500);
  if (error) throw new Error(error.message);
  return (((data as any)?.facilities) ?? []) as HealthcareFacility[];
}

export async function createFacility(input: Omit<HealthcareFacility, 'id' | 'is_active'>): Promise<HealthcareFacility> {
  const userId = (await supabase.auth.getUser()).data.user?.id;
  if (!userId) throw new Error('An authenticated administrator is required to create a facility.');
  const { data, error } = await reportsDb.rpc('create_reports_facility', { _name: input.name, _facility_code: input.facility_code, _facility_type: input.facility_type, _district: input.district, _region: input.region, _dhims2_uid: input.dhims2_uid });
  if (error) throw new Error(error.message);
  if (!data) throw new Error('Facility creation returned no facility record.');
  return data as HealthcareFacility;
}

export async function getFacilityNotificationConfig(facilityId: string): Promise<FacilityNotificationConfig | null> {
  const { data, error } = await reportsDb.from('facility_notification_config').select('facility_id,environment,enabled,default_locale,default_timezone,quiet_hours_start,quiet_hours_end,enabled_channels,rollout_percent,kill_switch,onboarding_status,branding,provider_defaults,delivery_policy,webhook_policy,compliance_policy,operational_contacts,deployment_secret_namespace,production_approved_at,production_approved_by').eq('facility_id', facilityId).maybeSingle();
  if (error) throw new Error(error.message);
  return (data ?? null) as FacilityNotificationConfig | null;
}

export async function listNotificationProviderSecretRequirements(): Promise<NotificationProviderSecretRequirement[]> {
  const { data, error } = await reportsDb.from('notification_provider_secret_requirements').select('id,provider,channel,secret_name,environment,required,description,secret_reference_example').order('channel').order('provider').order('secret_name');
  if (error) throw new Error(error.message);
  return (data ?? []) as NotificationProviderSecretRequirement[];
}

export async function initializeFacilityNotificationOnboarding(facilityId: string): Promise<FacilityNotificationConfig> {
  const { data, error } = await reportsDb.rpc('initialize_facility_notification_onboarding', { _facility_id: facilityId });
  if (error) throw new Error(error.message);
  if (!data) throw new Error('Notification onboarding returned no configuration.');
  return data as FacilityNotificationConfig;
}

export async function configureFacilityNotificationProvider(input: {
  facilityId: string; channel: 'email' | 'sms' | 'push' | 'whatsapp' | 'voice'; provider: string;
  environment: 'sandbox' | 'test' | 'production'; secretReference?: string | null; senderIdentity?: string | null; accountReference?: string | null;
}) {
  const { data, error } = await reportsDb.rpc('set_facility_notification_provider', {
    _facility_id: input.facilityId, _channel: input.channel, _provider: input.provider, _environment: input.environment,
    _secret_reference: input.secretReference ?? null, _sender_identity: input.senderIdentity ?? null,
    _account_reference: input.accountReference ?? null, _metadata: {}
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function listDefinitions(): Promise<ReportDefinition[]> {
  const { data, error } = await reportsDb.from('report_definitions').select('id,report_code,report_name,category_id,description,frequency,parameters,default_parameters,extractor_key,supported_formats,submission_deadline_day,is_active,implementation_status,report_categories(id,name,display_order)').eq('is_active', true).order('report_code');
  if (error) throw new Error(error.message);
  const rows = (data ?? []) as Array<Record<string, unknown>>;
  return rows.map((row) => { const categories = row.report_categories as ReportCategory[] | ReportCategory | null | undefined; return { ...row, category: Array.isArray(categories) ? categories[0] ?? null : categories ?? null, parameters: Array.isArray(row.parameters) ? row.parameters : [] }; }) as unknown as ReportDefinition[];
}

export async function listFacilityConfigs(facilityId: string): Promise<FacilityReportConfig[]> {
  const { data, error } = await reportsDb.from('facility_report_config').select('id,facility_id,report_id,is_enabled,submission_deadline_day,custom_parameters,report_definitions(id,report_code,report_name,category_id,description,frequency,parameters,default_parameters,extractor_key,supported_formats,submission_deadline_day,is_active,implementation_status,report_categories(id,name,display_order))').eq('facility_id', facilityId).order('report_id');
  if (error) throw new Error(error.message);
  const rows = (data ?? []) as Array<Record<string, unknown>>;
  return rows.map((row) => ({ ...row, report: row.report_definitions })) as unknown as FacilityReportConfig[];
}

export async function setReportEnabled(facilityId: string, reportId: string, enabled: boolean) {
  const { error } = await reportsDb.from('facility_report_config').upsert({ facility_id: facilityId, report_id: reportId, is_enabled: enabled }, { onConflict: 'facility_id,report_id' });
  if (error) throw new Error(error.message);
}

function dueDateFor(period: string, deadline: number) {
  const [year, month] = period.split('-').map(Number);
  const safeDeadline = Math.min(31, Math.max(1, Math.trunc(deadline || 1)));
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const effectiveDeadline = Math.min(safeDeadline, daysInMonth);
  return new Date(Date.UTC(year, month - 1, effectiveDeadline)).toISOString().slice(0, 10);
}

async function reconcileFailedRun(runId: string, reason: string): Promise<void> {
  const { data: currentItems, error: readError } = await reportsDb.from('report_generation_items').select('id,run_id,report_id,status,output_format,file_name,data_snapshot,validation_messages,error_message,started_at,completed_at,created_at').eq('run_id', runId).order('created_at');
  if (readError) throw new Error(`${reason} Unable to inspect run items: ${readError.message}`);
  const items = (currentItems ?? []) as ReportRunItem[];
  const incomplete = items.filter((item) => item.status === 'queued' || item.status === 'processing');
  if (incomplete.length) {
    const { error } = await reportsDb.from('report_generation_items').update({ status: 'failed', error_message: reason, completed_at: new Date().toISOString() }).eq('run_id', runId).in('status', ['queued', 'processing']);
    if (error) throw new Error(`${reason} Unable to mark incomplete report items as failed: ${error.message}`);
  }
  const { data: reconciledItems, error: reconciledReadError } = await reportsDb.from('report_generation_items').select('id,run_id,report_id,status,output_format,file_name,data_snapshot,validation_messages,error_message,started_at,completed_at,created_at').eq('run_id', runId).order('created_at');
  if (reconciledReadError) throw new Error(`${reason} Unable to re-read run items: ${reconciledReadError.message}`);
  const finalItems = (reconciledItems ?? []) as ReportRunItem[];
  const success = finalItems.filter((item) => item.status === 'completed').length;
  const warning = finalItems.filter((item) => item.status === 'warning').length;
  const failed = finalItems.filter((item) => item.status === 'failed').length;
  const finalStatus = finalItems.length === 0 || failed === finalItems.length ? 'failed' : 'partial_failed';
  const { error: finalError } = await reportsDb.from('report_generation_runs').update({ status: finalStatus, success_count: success, warning_count: warning, failed_count: failed, completed_at: new Date().toISOString() }).eq('id', runId);
  if (finalError) throw new Error(`${reason} Unable to finalize the failed report run: ${finalError.message}`);
}

export async function generateRun(facilityId: string, period: string, configs: FacilityReportConfig[]) {
  const { start, end } = monthBounds(period);
  // Re-read the facility configuration from the database instead of trusting client-supplied config objects.
  // The client may render stale/tampered configuration; persisted RLS-scoped state is authoritative for generation.
  const persistedConfigs = await listFacilityConfigs(facilityId);
  const enabled = persistedConfigs.filter((config) => config.is_enabled && config.report?.frequency === 'monthly');
  if (!enabled.length) throw new Error('No monthly reports are activated for this facility.');
  const userId = (await supabase.auth.getUser()).data.user?.id;
  if (!userId) throw new Error('An authenticated user is required to generate reports.');
  const now = new Date().toISOString();
  const { data: activeRuns, error: activeRunError } = await reportsDb.from('report_generation_runs').select('id,facility_id,period_start,period_end,frequency,status,total_reports,success_count,warning_count,failed_count,created_at,completed_at').eq('facility_id', facilityId).eq('period_start', start.slice(0, 10)).eq('period_end', end.slice(0, 10)).eq('frequency', 'monthly').in('status', ['queued', 'processing']).order('created_at', { ascending: false });
  if (activeRunError) throw new Error(activeRunError.message);
  for (const activeRun of (activeRuns ?? []) as ReportRun[]) { const result = await reportsDb.rpc('recover_stale_report_run', { _run_id: activeRun.id, _stale_after_minutes: 30 }); if (result.error) throw new Error(result.error.message); }
  const { data: runData, error: runError } = await reportsDb.from('report_generation_runs').insert({ facility_id: facilityId, period_start: start.slice(0, 10), period_end: end.slice(0, 10), frequency: 'monthly', status: 'processing', total_reports: enabled.length, created_by: userId, started_at: now, parameters: { period } }).select('id,facility_id,period_start,period_end,frequency,status,total_reports,success_count,warning_count,failed_count,created_at,completed_at').single();
  if (runError) { if (runError.message.toLowerCase().includes('uq_report_generation_active_run') || runError.message.toLowerCase().includes('duplicate key')) throw new Error('A report generation run for this facility and period is already in progress. Refresh the Reports Center and review the existing run.'); throw new Error(runError.message); }
  const run = runData as ReportRun;
  try {
    const { data: itemData, error: itemError } = await reportsDb.from('report_generation_items').insert(enabled.map((config) => ({ run_id: run.id, report_id: config.report_id, status: 'processing', output_format: 'xlsx', started_at: now }))).select('id,run_id,report_id,status,output_format,file_name,data_snapshot,validation_messages,error_message,started_at,completed_at,created_at');
    if (itemError) throw new Error(itemError.message);
    const items = itemData as ReportRunItem[];
    let success = 0; let warning = 0; let failed = 0;
    for (const item of items) {
      const config = enabled.find((entry) => entry.report_id === item.report_id);
      if (!config?.report) { failed += 1; const { error } = await reportsDb.from('report_generation_items').update({ status: 'failed', error_message: 'Report definition was not available for the activated configuration.', completed_at: new Date().toISOString() }).eq('id', item.id); if (error) throw new Error(error.message); continue; }
      const snapshot = await extractSnapshot(config.report, period);
      if (snapshot.error) {
        failed += 1;
        const { error } = await reportsDb.from('report_generation_items').update({ status: 'failed', data_snapshot: snapshot, validation_messages: [snapshot.error], error_message: snapshot.error, file_name: `${config.report.report_code}_${period}.xlsx`, completed_at: new Date().toISOString() }).eq('id', item.id);
        if (error) throw new Error(error.message);
        continue;
      }
      const hasWarning = Boolean(snapshot.warning); const status: ReportStatus = hasWarning ? 'warning' : 'completed';
      const { error: itemUpdateError } = await reportsDb.from('report_generation_items').update({ status, data_snapshot: snapshot, validation_messages: snapshot.warning ? [snapshot.warning] : [], file_name: `${config.report.report_code}_${period}.xlsx`, completed_at: new Date().toISOString() }).eq('id', item.id);
      if (itemUpdateError) { const { error } = await reportsDb.from('report_generation_items').update({ status: 'failed', error_message: itemUpdateError.message, completed_at: new Date().toISOString() }).eq('id', item.id); if (error) throw new Error(error.message); failed += 1; continue; }
      if (hasWarning) warning += 1; else success += 1;
      const submissionResult = await reportsDb.rpc('upsert_report_submission_tracking', { _report_id: config.report_id, _facility_id: facilityId, _period_start: start.slice(0, 10), _period_end: end.slice(0, 10), _due_date: dueDateFor(period, config.submission_deadline_day ?? config.report.submission_deadline_day), _data_snapshot: snapshot });
      if (submissionResult.error) { const { error } = await reportsDb.from('report_generation_items').update({ validation_messages: [...(snapshot.warning ? [snapshot.warning] : []), `Submission tracking could not be initialized: ${submissionResult.error.message}`], status: 'warning' }).eq('id', item.id); if (error) throw new Error(error.message); if (!hasWarning) { success -= 1; warning += 1; } }
    }
    const finalStatus = failed > 0 ? (failed === enabled.length ? 'failed' : 'partial_failed') : 'completed';
    const { data: finalData, error: finalError } = await reportsDb.from('report_generation_runs').update({ status: finalStatus, success_count: success, warning_count: warning, failed_count: failed, completed_at: new Date().toISOString() }).eq('id', run.id).select('id,facility_id,period_start,period_end,frequency,status,total_reports,success_count,warning_count,failed_count,created_at,completed_at').single();
    if (finalError) throw new Error(finalError.message);
    return finalData as ReportRun;
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'Report generation failed unexpectedly.';
    try { await reconcileFailedRun(run.id, reason); } catch (reconciliationError) { const reconciliationMessage = reconciliationError instanceof Error ? reconciliationError.message : 'Unable to reconcile the failed report run.'; throw new Error(`${reason} ${reconciliationMessage}`); }
    throw new Error(reason);
  }
}

export async function getRunItems(runId: string): Promise<ReportRunItem[]> { const { data, error } = await reportsDb.from('report_generation_items').select('id,run_id,report_id,status,output_format,file_name,data_snapshot,validation_messages,error_message,started_at,completed_at,created_at').eq('run_id', runId).order('created_at'); if (error) throw new Error(error.message); return (data ?? []) as ReportRunItem[]; }

export async function listSubmissions(facilityId: string, period: string): Promise<ReportSubmission[]> {
  const { start, end } = monthBounds(period); const periodStart = start.slice(0, 10); const periodEnd = end.slice(0, 10);
  const sync = await reportsDb.rpc('sync_overdue_report_submissions', { _facility_id: facilityId, _period_start: periodStart, _period_end: periodEnd }); if (sync.error) throw new Error(sync.error.message);
  const { data, error } = await reportsDb.from('report_submissions').select('id,report_id,facility_id,period_start,period_end,due_date,status,submitted_at,submitted_by,submission_reference').eq('facility_id', facilityId).eq('period_start', periodStart).eq('period_end', periodEnd).order('due_date'); if (error) throw new Error(error.message); return (data ?? []) as ReportSubmission[];
}

export async function markSubmissionsSubmitted(ids: string[]) { if (!ids.length) return; const result = await reportsDb.rpc('mark_report_submissions_submitted', { _submission_ids: ids }); if (result.error) throw new Error(result.error.message); }

function uniqueSheetName(rawName: string, used: Set<string>) {
  const base = (rawName.replace(/[:\\/?*[\]]/g, '').slice(0, 31) || 'Report').trim() || 'Report';
  let name = base; let suffix = 2;
  while (used.has(name.toLowerCase())) { const suffixText = `_${suffix++}`; name = `${base.slice(0, 31 - suffixText.length)}${suffixText}`; }
  used.add(name.toLowerCase()); return name;
}

export async function downloadRunWorkbook(run: ReportRun, items: ReportRunItem[], facility: HealthcareFacility) {
  const workbook = XLSX.utils.book_new(); const manifest = items.map((item) => ({ Report: item.file_name ?? item.report_id, Status: item.status, Source: item.data_snapshot.source, Total: item.data_snapshot.total, Warnings: item.validation_messages.join(' | ') })); XLSX.utils.book_append_sheet(workbook, XLSX.utils.json_to_sheet(manifest), 'Manifest');
  const used = new Set<string>(['manifest']);
  for (const item of items) { const rows = item.data_snapshot.by_dimension.map((row) => ({ Dimension: row.dimension, Value: row.value, Count: row.count })); if (!rows.length) rows.push({ Dimension: 'status', Value: item.status, Count: item.data_snapshot.total }); const sheetName = uniqueSheetName(item.file_name ?? item.report_id, used); XLSX.utils.book_append_sheet(workbook, XLSX.utils.json_to_sheet(rows), sheetName); }
  XLSX.writeFile(workbook, `reports_${facility.facility_code ?? facility.id}_${run.period_start.slice(0, 7)}.xlsx`);
}

export function downloadManifestCsv(run: ReportRun, items: ReportRunItem[], facility: HealthcareFacility) {
  const lines = ['Report,Status,Source,Total,Warnings'];
  for (const item of items) lines.push([item.file_name ?? item.report_id, item.status, item.data_snapshot.source, String(item.data_snapshot.total), item.validation_messages.join('; ')].map((value) => `"${value.replace(/"/g, '""')}"`).join(','));
  const blob = new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8;' }); const url = URL.createObjectURL(blob); const anchor = document.createElement('a'); anchor.href = url; anchor.download = `reports_manifest_${facility.facility_code ?? facility.id}_${run.period_start.slice(0, 7)}.csv`; anchor.click(); URL.revokeObjectURL(url);
}
