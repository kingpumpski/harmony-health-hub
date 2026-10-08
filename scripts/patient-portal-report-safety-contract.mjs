import fs from 'node:fs';

const portal = fs.readFileSync('src/pages/PatientPortal.tsx', 'utf8');
const requestStart = portal.indexOf('const requestAIReport = async () =>');
const requestEnd = portal.indexOf('\n  const speakReport', requestStart);
if (requestStart < 0 || requestEnd < 0) throw new Error('Patient portal AI report request handler is missing');
const handler = portal.slice(requestStart, requestEnd);
for (const needle of [
  'let requestId: string | null = null;',
  "typeof data?.content !== 'string'",
  "_request_id: requestId",
  "_content: null,",
  '_error: message,',
  'await loadReports();',
]) if (!handler.includes(needle)) throw new Error('AI report lifecycle missing: ' + needle);
if (!handler.includes('if (requestId)')) throw new Error('Failed AI report requests must be marked failed when a request was created');

const printStart = portal.indexOf('const printReport =');
const printEnd = portal.indexOf('\n  };', printStart);
const printHandler = portal.slice(printStart, printEnd);
for (const needle of ["text.replace(/[&<>\"']/g", "'&': '&amp;'", "'<': '&lt;'", "'\\\"': '&quot;'"]) {
  if (!printHandler.includes(needle)) throw new Error('Printable report HTML escaping missing: ' + needle);
}
console.log('Patient portal AI report lifecycle and print-safety contract passed.');
