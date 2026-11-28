import assert from 'node:assert/strict';
import fs from 'node:fs';

const workflow = fs.readFileSync('.github/workflows/supabase-database.yml', 'utf8');
assert.match(workflow, /^on:\n  workflow_dispatch:\n/m, 'production compatibility review must be manually dispatched only');
assert.doesNotMatch(workflow, /^  push:/m, 'production compatibility review must never run automatically on push');
assert.doesNotMatch(workflow, /SUPABASE_ACCESS_TOKEN|SUPABASE_PROJECT_REF|supabase link|supabase db query|supabase db push|supabase migration up/, 'review workflow must not obtain credentials, link, or execute SQL');
assert.match(workflow, /test ! -e supabase\/production-hotfix\.sql/, 'active production hotfix path must remain absent');
assert.match(workflow, /docs\/engineering\/migration-source-candidates\/production-hotfix\.sql\.candidate/, 'archived hotfix source must remain available for review');
const candidate = fs.readFileSync('docs/engineering/migration-source-candidates/production-hotfix.sql.candidate', 'utf8');
assert.match(candidate, /CREATE OR REPLACE FUNCTION public\.create_admission_workflow/, 'archived hotfix must retain original source for review');
assert.match(candidate, /UPDATE public\.invoice_items/, 'archived data backfill must remain visible for review');
console.log('[production-hotfix-safety] production SQL cannot run automatically or through this workflow; original SQL is preserved inactive.');
