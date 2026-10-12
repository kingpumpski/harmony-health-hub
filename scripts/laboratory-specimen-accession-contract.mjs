import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/20261012170000_laboratory_specimen_accession_and_rejection.sql', import.meta.url), 'utf8');
const source = readFileSync(new URL('../src/pages/Laboratory.tsx', import.meta.url), 'utf8');
const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.lab_specimens/, 'specimen identity must be persisted in a dedicated table');
assert.match(migration, /accession_number text NOT NULL UNIQUE/, 'each specimen must have a unique accession number');
assert.match(migration, /barcode_value text NOT NULL UNIQUE/, 'each specimen must have a unique barcode value');
assert.match(migration, /idx_lab_specimens_one_active_per_order/, 'a laboratory order must not have multiple active primary specimens');
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.collect_lab_sample/, 'sample collection must be replaced with the atomic accession workflow');
assert.match(migration, /INSERT INTO public\.lab_specimens/, 'specimen accession must be persisted in the collection transaction');
assert.match(migration, /Payment approval required before sample collection/, 'payment gate must remain before collection');
assert.match(migration, /Laboratory order belongs to a different facility context/, 'collection must preserve active-facility isolation');
assert.equal((migration.match(/Laboratory order and patient facility lineage do not match/g) ?? []).length, 2, 'collection and rejection must validate patient-to-order facility lineage');
assert.equal((migration.match(/Laboratory patient facility attribution is unresolved/g) ?? []).length, 2, 'collection and rejection must fail closed for unresolved patient facility attribution');
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.reject_lab_specimen/, 'specimen rejection must use a governed RPC');
assert.match(migration, /Provide a specimen rejection reason between 3 and 1000 characters/, 'rejection reason must be validated server-side');
assert.match(migration, /status='ordered', collected_by=NULL, sample_collected_at=NULL/, 'rejection must allow controlled recollection without erasing the rejected specimen');
assert.match(migration, /recollection_of_id\s*\) VALUES[\s\S]*v_previous_specimen_id/, 'recollection must link the new specimen to the rejected specimen');
assert.match(migration, /v_department text/, 'specimen reads must apply department-aware role authorization');
assert.match(migration, /public\.has_role\(uid,'lab_technician'\) AND \(v_department IS NULL OR v_department='laboratory'\)/, 'specimen reads must be restricted to laboratory technicians in the laboratory department');
assert.doesNotMatch(migration, /OR public\.has_role\(uid,'practitioner'\)|OR public\.has_role\(uid,'nurse'\)|OR public\.has_role\(uid,'midwife'\)|OR public\.has_role\(uid,'specialist_nurse'\)|OR public\.has_role\(uid,'radiologist'\)/, 'specimen listing must not expand access to non-laboratory clinical workspaces');
assert.match(migration, /REVOKE ALL ON TABLE public\.lab_specimens FROM PUBLIC, anon, authenticated/, 'direct client table access must be denied');
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.get_laboratory_specimens/, 'specimen reads must use a facility-scoped RPC');
assert.match(migration, /WHERE o\.facility_id=v_facility/, 'specimen read RPC must scope orders to the active facility');
assert.match(migration, /REVOKE ALL ON FUNCTION public\.reject_lab_specimen\(uuid,text\) FROM PUBLIC, anon/, 'rejection RPC must not be executable anonymously');
assert.match(source, /get_laboratory_specimens/, 'laboratory UI must load specimen accession records');
assert.match(source, /accession_number/, 'laboratory UI must display accession identifiers');
assert.match(source, /Barcode value:/, 'laboratory UI must display barcode values');
assert.match(source, /reject_lab_specimen/, 'laboratory UI must submit rejection through the governed RPC');
assert.match(source, /Required rejection reason/, 'laboratory UI must explain the rejection reason requirement');
assert.match(packageJson.scripts.test, /test:laboratory-specimen-accession/, 'specimen contract must be part of the required test chain');
assert.equal(packageJson.scripts['test:laboratory-specimen-accession'], 'node scripts/laboratory-specimen-accession-contract.mjs');

assert.match(migration, /A laboratory result already exists; specimen rejection is no longer permitted/, 'specimen rejection must be blocked when any result row already exists');

console.log('Laboratory specimen accession contract passed.');
