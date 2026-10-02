import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261002120000_pharmacy_inventory_catalogue_management.sql', 'utf8');
const page = fs.readFileSync('src/pages/Pharmacy.tsx', 'utf8');

for (const needle of [
  "public.current_user_has_catalogue_create_permission('create_items')",
  "public.has_role(v_uid, 'it_admin')",
  "'inventory'",
  "CASE WHEN v_clinical_pharmacy THEN",
  "p.facility_id = v_facility",
  "CREATE OR REPLACE FUNCTION public.update_pharmacy_inventory_item",
  "public.record_system_audit",
  "REVOKE ALL ON FUNCTION public.update_pharmacy_inventory_item",
  "GRANT EXECUTE ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric) TO authenticated"
]) {
  if (!migration.includes(needle)) throw new Error('Pharmacy inventory migration missing security/management contract: ' + needle);
}

for (const needle of [
  "db.rpc('get_pharmacy_workspace'",
  "db.rpc('update_pharmacy_inventory_item'",
  "db.rpc('create_pharmacy_inventory_item'",
  "const editInventoryItem = (item: InventoryItem)",
  "Save changes",
  "canCreateItems && <form",
  "onClick={() => editInventoryItem(item)}"
]) {
  if (!page.includes(needle)) throw new Error('Pharmacy inventory UI missing management contract: ' + needle);
}

console.log('Pharmacy inventory management access and update contract passed');
