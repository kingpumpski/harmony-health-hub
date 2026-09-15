import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const registryPath = path.join(root, 'platform/reference/module-registry.json');
const migrationPath = path.join(root, 'supabase/migrations/20260915150000_nextgen_platform_foundation.sql');
const registry = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
const migration = fs.readFileSync(migrationPath, 'utf8');

if (registry.schemaVersion !== '1.0.0') throw new Error('Unexpected module registry schema version');
if (!Array.isArray(registry.modules) || registry.modules.length < 1) throw new Error('Module registry is empty');
const ids = registry.modules.map((module) => module.id);
if (new Set(ids).size !== ids.length) throw new Error('Module registry contains duplicate module IDs');
if (!migration.includes('ALTER TABLE public.platform_deployment_profiles ENABLE ROW LEVEL SECURITY;')) throw new Error('Deployment profile RLS is missing');
if (!migration.includes('ALTER TABLE public.platform_ai_model_registry ENABLE ROW LEVEL SECURITY;')) throw new Error('AI registry RLS is missing');
if (!migration.includes('CREATE POLICY "users manage own accessibility preferences"')) throw new Error('Accessibility ownership policy is missing');
if (!migration.includes('CHECK (lifecycle_state IN (\'proposed\',\'validated\',\'approved\',\'active\',\'restricted\',\'suspended\',\'retired\'))')) throw new Error('AI lifecycle guard is missing');
if (!migration.includes('CHECK (lifecycle_state IN (\'proposed\',\'onboarding\',\'validation\',\'active\',\'degraded\',\'quarantined\',\'maintenance\',\'retired\'))')) throw new Error('Device lifecycle guard is missing');
if (migration.includes('service_role') && migration.includes('GRANT ALL ON')) throw new Error('Broad GRANT ALL detected in platform foundation migration');

console.log(`Next-gen contract verification passed: ${ids.length} registered modules; RLS, lifecycle and ownership checks present.`);
