import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql', 'utf8');
const page = fs.readFileSync('src/pages/Pharmacy.tsx', 'utf8');
const modal = fs.readFileSync('src/components/catalogue/CatalogueCreateModal.tsx', 'utf8');
const shell = fs.readFileSync('src/components/workflow/OperationalWorklistShell.tsx', 'utf8');
const clinicalTable = fs.readFileSync('src/components/workflow/ClinicalDataTable.tsx', 'utf8');

for (const needle of [
  'CREATE TABLE IF NOT EXISTS public.medication_catalogue',
  'category text NOT NULL DEFAULT',
  'ADD COLUMN IF NOT EXISTS facility_id uuid REFERENCES public.healthcare_facilities(id)',
  'ADD COLUMN IF NOT EXISTS catalogue_id uuid REFERENCES public.medication_catalogue(id)',
  'i.facility_id = v_facility',
  'public.add_global_medication_to_facility',
  'nhis_patient_price, nhis_claim_amount',
  'WHERE i.active AND i.facility_id = fid AND i.stock_quantity > 0',
  "IF source_category IS NULL OR lower(btrim(source_category)) = 'uncategorized' THEN RETURN;",
  'prescriber authorization and clinical reason',
  'dispensed_quantity = next_dispensed',
  `'nhis_claim_amount', claim`,
  'public.assign_unattributed_pharmacy_inventory',
  'REVOKE INSERT, UPDATE, DELETE ON public.pharmacy_inventory FROM PUBLIC, anon, authenticated'
]) {
  if (!migration.includes(needle)) throw new Error('Pharmacy safety migration missing: ' + needle);
}

for (const needle of [
  'import ClinicalDataTable, { ClinicalProgressBar, ClinicalStatusBadge, ClinicalTableAction }',
  'setCatalogue(workspace.catalogue ?? [])',
  'setUnassignedInventory(workspace.unassigned_inventory ?? [])',
  'Patient clinical safety context',
  'prescription.patients?.allergies',
  'prescription.diagnosis',
  'Find in-stock alternatives',
  'alternativeReasons[prescription.id]',
  'nhis_patient_price',
  'nhis_claim_amount',
  'Barcode scan',
  'add_global_medication_to_facility',
  'Assign to active facility',
  'placeholder="Scan medication barcode, then press Enter"',
  'disabled={Boolean(editingInventoryId)}'
]) {
  if (!page.includes(needle)) throw new Error('Pharmacy safety UI missing: ' + needle);
}
if (!modal.includes('_category: category || \'Uncategorized\'')) throw new Error('Medication category is not passed to the global catalogue RPC.');
if (!clinicalTable.includes('export function ClinicalProgressBar(')) throw new Error('ClinicalProgressBar export must remain available.');
if (!shell.includes('xl:grid-cols-5') || !shell.includes('text-xl font-bold')) throw new Error('Operational KPI cards must be compact and fit five columns on wide screens.');

console.log('Pharmacy global catalogue, facility isolation and dispensing safety contract passed');
