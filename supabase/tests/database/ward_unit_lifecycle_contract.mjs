import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync('supabase/migrations/20260924132000_harden_ward_unit_lifecycle.sql','utf8');

const checks=[
 [/public\.ward_units\(name, code, specialty, gender_policy, active\)/i,'canonical ward-unit insert missing'],
 [/lower\(btrim\(name\)\)/i,'normalized ward-name uniqueness missing'],
 [/lower\(btrim\(code\)\)/i,'normalized ward-code uniqueness missing'],
 [/Cannot deactivate ward with occupied or patient-linked beds/i,'deactivation safety guard missing'],
 [/public\.ward_beds/i,'ward-bed lifecycle linkage missing'],
 [/CREATE OR REPLACE FUNCTION public\.update_ward_unit\(uuid,?\s*_name/i,'ward-unit update RPC missing'],
 [/CREATE OR REPLACE FUNCTION public\.set_ward_unit_active/i,'ward-unit activation RPC missing'],
 [/REVOKE ALL ON FUNCTION public\.create_ward_unit\(text, text, text, text\) FROM PUBLIC, anon/i,'create execute revoke missing'],
 [/REVOKE ALL ON FUNCTION public\.update_ward_unit\(uuid, text, text, text, text, boolean\) FROM PUBLIC, anon/i,'update execute revoke missing'],
 [/REVOKE ALL ON FUNCTION public\.set_ward_unit_active\(uuid, boolean\) FROM PUBLIC, anon/i,'activation execute revoke missing'],
 [/REVOKE INSERT, UPDATE, DELETE ON public\.ward_units FROM authenticated/i,'direct client write lock missing']
];

for (const [pattern,message] of checks) assert.match(migration,pattern,message);
console.log('ward-unit lifecycle contract passed');
