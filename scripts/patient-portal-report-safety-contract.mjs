import fs from 'node:fs';

const portal = fs.readFileSync('src/pages/PatientPortal.tsx', 'utf8');
const requestStart = portal.indexOf('const requestAIReport = async () =>');
const requestEnd = portal.indexOf('\n  const speakReport', requestStart);
if (requestStart < 0 || requestEnd < 0) throw new Error('Patient portal AI report request handler is missing');
const handler = portal.slice(requestStart, requestEnd);
for (const needle of [
  'let requestId: string | null = null;',
  "typeof data?.content !== 'string'",
  'reportRequestId: requestId',
  "rpc('fail_ai_report_request'",
  '_request_id: requestId',
  '_error: message,',
  'await loadReports();',
]) if (!handler.includes(needle)) throw new Error('AI report lifecycle missing: ' + needle);
if (!handler.includes('if (requestId)')) throw new Error('Failed AI report requests must be marked failed when a request was created');
if (portal.includes("rpc('complete_ai_report_request'")) throw new Error('Patient clients must not complete AI report content directly');

const edge = fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts', 'utf8');
const completionMigration = fs.readFileSync('supabase/migrations/20261009051000_harden_ai_report_completion_authority.sql', 'utf8');
for (const needle of [
  'SUPABASE_SERVICE_ROLE_KEY',
  "rpc('complete_ai_report_request'",
  ".eq('requested_by', callerId)",
  ".eq('status', 'processing')",
  'authorizedPatientReportRequestId',
]) if (!edge.includes(needle)) throw new Error('Trusted AI report completion path missing: ' + needle);
for (const needle of [
  "current_setting('request.jwt.claim.role', true) IS DISTINCT FROM 'service_role'",
  'FROM PUBLIC, anon, authenticated',
  'TO service_role',
  'CREATE OR REPLACE FUNCTION public.fail_ai_report_request',
  'FROM PUBLIC, anon',
  'TO authenticated',
]) if (!completionMigration.includes(needle)) throw new Error('AI report completion authorization migration missing: ' + needle);


const printStart = portal.indexOf('const printReport =');
const printEnd = portal.indexOf('\n  };', printStart);
const printHandler = portal.slice(printStart, printEnd);
for (const needle of ["text.replace(/[&<>\"']/g", "'&': '&amp;'", "'<': '&lt;'", "'\\\"': '&quot;'"]) {
  if (!printHandler.includes(needle)) throw new Error('Printable report HTML escaping missing: ' + needle);
}
console.log('Patient portal AI report lifecycle and print-safety contract passed.');
