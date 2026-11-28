import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const sourceRoot = join(root, 'src');
const files = [];
function walk(directory) {
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);
    const stat = statSync(path);
    if (stat.isDirectory()) walk(path);
    else if (/\.[cm]?[jt]sx?$/.test(entry)) files.push(path);
  }
}
walk(sourceRoot);

const directWrite = /\.from\(\s*['"]report_submissions['"]\s*\)\s*\.\s*(?:insert|update|upsert|delete)\s*\(/;
const writers = files.filter((path) => directWrite.test(readFileSync(path, 'utf8')));
assert.deepEqual(writers, [], 'Reports Center must not write report_submissions directly from the client');

const reportsCenter = readFileSync(join(sourceRoot, 'lib', 'reportsCenter.ts'), 'utf8');
assert.match(reportsCenter, /\.from\('report_submissions'\)\.select\(/, 'Reports Center must retain facility-scoped direct reads');
assert.match(reportsCenter, /rpc\('mark_report_submissions_submitted'/, 'submission transitions must use the governed RPC');
assert.match(reportsCenter, /rpc\('upsert_report_submission_tracking'/, 'submission tracking writes must use the governed RPC');

const databaseContract = readFileSync(join(root, 'supabase', 'tests', 'database', 'report_submissions_readonly_contract.sql'), 'utf8');
assert.match(databaseContract, /has_table_privilege[\s\S]*INSERT[\s\S]*UPDATE/, 'database contract must assert direct write privileges are absent');

console.log('[report-submissions-readonly] Reports Center write path contract passed');
