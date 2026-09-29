import fs from 'node:fs';
import assert from 'node:assert/strict';

const read = (p) => fs.readFileSync(p, 'utf8');
const migration = read('supabase/migrations/20260929150000_canteen_dietary_operational_workspace.sql');
const realtimeFix = read('supabase/migrations/20260929151500_fix_canteen_realtime_topic_authorization.sql');
const contextFix = read('supabase/migrations/20260929152000_restrict_canteen_patient_context_fields.sql');
const ui = read('src/pages/CanteenMeals.tsx');
const app = read('src/App.tsx');

assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.meal_menus/);
assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.meal_menu_items/);
assert.match(migration, /UNIQUE\(service_date, meal_period\)/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.save_canteen_menu/);
assert.match(migration, /has_role\(uid,'canteen'\)/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.get_canteen_active_patient_orders/);
assert.match(migration, /p\.chronic_conditions/);
assert.match(contextFix, /RETURNS TABLE/);
assert.doesNotMatch(contextFix, /meal_notes/);
assert.match(migration, /FROM public\.diagnoses d/);
assert.match(migration, /e\.status NOT IN \('completed','cancelled'\)/);
assert.match(migration, /realtime\.send/);
assert.match(migration, /'canteen_context_changed'/);
assert.match(realtimeFix, /realtime\.topic\(\) = 'canteen:operations'/);
assert.match(migration, /realtime:can\w+:operations/);
assert.match(ui, /get_canteen_active_patient_orders/);
assert.match(ui, /current_diagnoses/);
assert.match(ui, /Underlying conditions/);
assert.match(ui, /Create or update a menu/);
assert.match(ui, /save_canteen_menu/);
assert.match(ui, /canteen_context_changed/);
assert.match(ui, /Clinical context is displayed to support meal-service safety/);
assert.doesNotMatch(ui, /searchPatientDirectory/);
assert.doesNotMatch(ui, /meal_notes/);
assert.match(app, /<Route path="\/menu" element={<CanteenMeals \/>} \/>/);

console.log('Canteen dietary operational contract: 22 assertions passed');