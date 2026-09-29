import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260929200000_fix_canteen_menu_rbac_realtime.sql','utf8');
const ui=fs.readFileSync('src/pages/CanteenMeals.tsx','utf8');

assert.match(migration,/meal_menus_authenticated_read/);
assert.match(migration,/meal_menu_items_authenticated_read/);
assert.match(migration,/current_user_has_role\('canteen'/);
assert.match(migration,/realtime\.topic\(\) = 'canteen:operations'/);
assert.doesNotMatch(migration,/public\.has_role\(/);
assert.match(migration,/ALTER FUNCTION public\.has_role\(uuid, public\.app_role\)/);
assert.match(ui,/channel\('canteen:operations', \{ config: \{ private: true \} \}\)/);
assert.match(ui,/supabase\.realtime\.setAuth\(\)/);
assert.match(ui,/from\('meal_menus'\)/);
console.log('Canteen menu RBAC/realtime contract passed.');
