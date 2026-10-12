import fs from 'node:fs';
import assert from 'node:assert/strict';

const source = fs.readFileSync('src/pages/PatientPortal.tsx', 'utf8');
const loadStart = source.indexOf('const loadReports = async () => {');
const identityStart = source.indexOf("supabase.rpc('get_patient_portal_identity', {})", loadStart);
const identityGuard = source.slice(source.indexOf('let identity: any', loadStart), source.indexOf('if (version !== loadVersion.current) return null;', identityStart));
assert.notEqual(loadStart, -1, 'Patient portal must retain its shared loader');
assert.match(identityGuard, /try \{[\s\S]*?get_patient_portal_identity[\s\S]*?catch \(error: any\)/, 'identity RPC transport rejections must be caught');
const failureBranch = source.slice(source.indexOf('if (identityError || !portalPatient)', identityStart), source.indexOf('const requests = await Promise.allSettled', identityStart));
for (const clear of ['setPatient(null)', 'setAppts([])', 'setSessions([])', 'setInvoices([])', 'setReports([])', 'setClinicalSnapshot(null)']) assert.ok(failureBranch.includes(clear), 'identity failure must clear stale portal data: '+clear);
assert.match(failureBranch, /identityError\?\.message/, 'identity failure should expose a useful error message');
console.log('Patient portal identity network resilience contract passed.');

const reportHandler = source.slice(source.indexOf('const requestAIReport = async'), source.indexOf('const speakReport ='));
assert.match(reportHandler, /Report ready; portal refresh failed/, 'a successful report must remain successful if refreshing the portal fails');
assert.match(reportHandler, /catch \(failureUpdateError: any\)/, 'a rejected failure-status RPC must not suppress the original report error notification');
assert.match(reportHandler, /catch \(refreshError: any\)/, 'report status refresh rejection must be handled');
