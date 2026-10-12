import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/InpatientManagement.tsx', import.meta.url), 'utf8');

assert.match(source, /const loadSummary = useCallback\(async \(\) => \{/);
assert.match(source, /try \{[\s\S]*?supabase\.rpc\('get_admission_workspace'/);
assert.match(source, /catch \(error\) \{[\s\S]*?setSummary\(emptySummary\)/);
assert.match(source, /finally \{\s*setLoading\(false\);\s*\}/);
assert.match(source, /onClick=\{\(\) => void loadSummary\(\)\} className="btn-secondary mt-3">Retry/);

console.log('Inpatient summary resilience contract passed.');
