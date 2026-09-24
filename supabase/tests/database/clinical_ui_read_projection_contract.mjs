import fs from 'node:fs';

const cases = [
  ['src/pages/Dental.tsx', "select('id,patient_id,examination,treatment_plan,procedures_performed,created_at')"],
  ['src/pages/Ophthalmology.tsx', "select('id,patient_id,visual_acuity,refraction,keratometry,intraocular_pressure,color_vision,fundus_notes,status,created_at')"],
  ['src/pages/Fertility.tsx', "select('id,patient_id,partner_name,cycle_type,cycle_number,start_date,expected_retrieval_date,expected_transfer_date,protocol,status,outcome,notes')"],
  ['src/pages/Fertility.tsx', "select('id,cycle_id,visit_date,cycle_day,estradiol,lh,fsh,progesterone,follicle_count_left,follicle_count_right,endometrial_thickness,medication_adjustments,notes')"],
  ['src/pages/CareTransitions.tsx', "select('id,patient_id,destination,specialty,reason,urgency,status,clinical_summary,created_at')"],
  ['src/pages/CareTransitions.tsx', "select('id,patient_id,transition_type,status,destination,summary,medications_reconciled,follow_up_required,follow_up_date,instructions,created_at')"],
  ['src/contexts/AuthContext.tsx', "select('id,first_name,last_name,department,specialization')"],
  ['src/pages/admin/Settings.tsx', "select('id,facility_name,facility_code,phone,email,address,country,currency,timezone,routing_mode,appointment_buffer_minutes,maintenance_mode,allow_treatment_before_deposit,admission_financial_override_enabled,require_accounts_release_after_deposit,allow_clinical_emergency_override')"],
];

for (const [file, projection] of cases) {
  const content = fs.readFileSync(file, 'utf8');
  if (!content.includes(projection)) throw new Error(`Expected explicit projection missing: ${file}`);
  if (content.includes(".select('*')")) throw new Error(`Broad select('*') remains in protected UI surface: ${file}`);
}
console.log('Clinical UI read projection contract passed');
