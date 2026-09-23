import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260923190000_harden_current_user_helper_execute_boundary.sql',
  'utf8',
);

assert.match(migration,/REVOKE EXECUTE ON FUNCTION public\.current_user_has_role\(public\.app_role\)[\\s\\S]*?FROM authenticated, anon, public/i);
assert.match(migration,/REVOKE EXECUTE ON FUNCTION public\.current_user_is_clinical_staff\(\)[\\s\\S]*?FROM authenticated, anon, public/i);
assert.match(migration,/REVOKE EXECUTE ON FUNCTION public\.current_user_can_edit_patient_record\(\)[\\s\\S]*?FROM authenticated, anon, public/i);

console.log('current-user authorization helper execute boundary contract passed');
