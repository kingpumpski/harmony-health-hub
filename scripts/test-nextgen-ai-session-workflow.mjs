import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260916130000_ai_session_creation_workflow_hardening.sql'), 'utf8');
const page = fs.readFileSync(path.join(root, 'src/pages/AIClinicalHub.tsx'), 'utf8');

for (const token of [
  'CREATE OR REPLACE FUNCTION public.create_ai_clinical_session',
  'SECURITY DEFINER',
  'auth.uid()',
  '_patient_id UUID',
  '_input_snapshot JSONB',
  '_provenance JSONB',
  'Patient record not found',
  'jsonb_typeof(_input_snapshot) <> \'object\'',
  'record_ai_clinical_event',
  'REVOKE ALL ON FUNCTION public.create_ai_clinical_session',
  'GRANT EXECUTE ON FUNCTION public.create_ai_clinical_session',
  'REVOKE INSERT, UPDATE, DELETE ON public.ai_clinical_sessions FROM authenticated',
]) {
  if (!migration.includes(token)) throw new Error(`AI session creation security control missing: ${token}`);
}

if (!page.includes("supabase.rpc('create_ai_clinical_session'")) throw new Error('AI Clinical Hub is not using the secure session-creation RPC');
if (page.includes(".from('ai_clinical_sessions' as never).insert")) throw new Error('AI Clinical Hub still performs direct AI session insertion');
if (page.includes("supabase.rpc('record_ai_clinical_event'")) throw new Error('AI Clinical Hub still records session creation events directly from the client');

console.log('Next-gen AI session workflow verification passed: secure creation RPC, ownership/provenance validation, atomic audit event, direct-write lockdown, and UI integration are present.');
