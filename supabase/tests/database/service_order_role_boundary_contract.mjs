import fs from 'node:fs'; import assert from 'node:assert/strict';
const m=fs.readFileSync('supabase/migrations/20260928154500_harden_service_order_role_boundaries.sql','utf8');
for(const fn of ['cancel_service_order','create_anesthetic_assessment','create_service_order']){
 assert.ok(m.includes('CREATE OR REPLACE FUNCTION public.'+fn));
 assert.ok(m.includes('REVOKE ALL ON FUNCTION public.'+fn));
}
assert.equal(m.includes('is_clinical_staff('),false);
assert.ok(m.includes("e.id=_encounter_id AND e.patient_id=_patient_id"));
assert.ok(m.includes("public.has_role(auth.uid(),'accountant')"));
