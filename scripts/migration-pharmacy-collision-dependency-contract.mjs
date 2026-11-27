import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('../supabase/migrations/', import.meta.url);
const cataloguePath = new URL('20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql', root);
const categoryPath = new URL('20261002132500_pharmacy_global_category_edit.sql', root);
const catalogue = readFileSync(cataloguePath, 'utf8');
const category = readFileSync(categoryPath, 'utf8');

function functionDefinition(source, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(
    `CREATE(?: OR REPLACE)? FUNCTION public\\.${escaped}\\([\\s\\S]*?\\$function\\$;`,
    'i',
  ));
  assert.ok(match, `Expected function definition for public.${name}`);
  return match[0].replace(/\\s+/g, ' ').trim();
}

// Both files were touched by the same Git commit, so Git ancestry cannot order them.
// Pin their overlapping function definitions to identical normalized source.
for (const name of ['assign_unattributed_pharmacy_inventory', 'update_pharmacy_inventory_item']) {
  assert.equal(
    functionDefinition(catalogue, name),
    functionDefinition(category, name),
    `Colliding pharmacy migrations must not drift in their duplicate public.${name} definition`,
  );
}

// The later category-edit migration consumes columns introduced by the earlier catalogue migration.
assert.ok(catalogue.includes('ALTER TABLE public.pharmacy_inventory'), 'catalogue migration must alter the inventory table');
for (const column of ['catalogue_id', 'facility_id', 'barcode', 'nhis_patient_price', 'nhis_claim_amount']) {
  assert.match(
    catalogue,
    new RegExp(`ADD COLUMN IF NOT EXISTS ${column}\\b`),
    `catalogue migration must introduce pharmacy_inventory.${column}`,
  );
}
assert.ok(category.includes('r.catalogue_id'), 'category-edit RPC depends on the catalogue_id row field');
assert.ok(category.includes('barcode = NULLIF'), 'category-edit RPC depends on the barcode column');
assert.ok(category.includes('nhis_patient_price = COALESCE'), 'category-edit RPC depends on the NHIS patient-price column');
assert.ok(category.includes('nhis_claim_amount = COALESCE'), 'category-edit RPC depends on the NHIS claim column');

const catalogueVersion = '20261002130000';
const categoryVersion = '20261002132500';
assert.ok(catalogueVersion < categoryVersion, 'catalogue schema prerequisite must precede category-edit migration by version');

console.log('[pharmacy-collision-dependency] PASS: duplicated RPC definitions are source-equivalent and category-edit prerequisites are explicit.');
