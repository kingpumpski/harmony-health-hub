import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/20261014103413_lab_specimens_explicit_deny_policy.sql', import.meta.url), 'utf8').toLowerCase();
const accession = readFileSync(new URL('../supabase/migrations/20261012170000_laboratory_specimen_accession_and_rejection.sql', import.meta.url), 'utf8');

for (const token of [
  'alter table public.lab_specimens enable row level security',
  'revoke all on table public.lab_specimens from public, anon, authenticated',
  'lab_specimens_deny_direct_client_access',
  'for all',
  'to anon, authenticated',
  'using (false)',
  'with check (false)',
]) assert(migration.includes(token), 'Specimen direct-access lockdown missing: ' + token);

assert.match(accession, /REVOKE ALL ON TABLE public\.lab_specimens FROM PUBLIC, anon, authenticated/i, 'specimen records must remain inaccessible directly to client roles');
assert.match(accession, /CREATE OR REPLACE FUNCTION public\.get_laboratory_specimens/i, 'authorized specimen reads must use the governed RPC');
assert.match(accession, /CREATE OR REPLACE FUNCTION public\.collect_lab_sample/i, 'specimen collection must use the governed RPC');
assert.match(accession, /CREATE OR REPLACE FUNCTION public\.reject_lab_specimen/i, 'specimen rejection must use the governed RPC');

console.log('Laboratory specimen RLS deny policy contract passed.');
