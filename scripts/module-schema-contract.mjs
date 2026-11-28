import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const typesPath = 'src/integrations/supabase/types.ts';
const types = readFileSync(typesPath, 'utf8');

// This contract is intentionally checked against the generated Database type,
// which is refreshed from the canonical Supabase catalog. It catches missing
// module tables and column drift before application code is released.
const tablePattern = new RegExp(String.raw`^      ([a-z][a-z0-9_]*): \{\n        Row: \{\n([\s\S]*?)\n        \}\n        Insert:`, 'gm');
const tables = new Map();
for (const match of types.matchAll(tablePattern)) {
  const columns = [...match[2].matchAll(/^          ([a-z][a-z0-9_]*):/gm)].map((item) => item[1]);
  tables.set(match[1], new Set(columns));
}

assert.ok(tables.size >= 150, `expected a complete public table type inventory; found ${tables.size}`);

const moduleContracts = {
  patient_registration: ['patients:id,patient_code,first_name,last_name,date_of_birth,facility_id'],
  appointments: ['appointments:id,patient_id,scheduled_at,status,appointment_date,provider_id,facility_id'],
  clinical_encounters: ['encounters:id,patient_id,appointment_id,practitioner_id,encounter_type,status,facility_id'],
  vital_signs_and_triage: ['vital_signs:id,patient_id,recorded_by,recorded_at,encounter_id,facility_id', 'triage_assessments:id,patient_id,recorded_by,priority,is_critical,facility_id'],
  inpatient_admission: ['admissions:id,patient_id,admitted_at,discharged_at,status,encounter_id,facility_id', 'inpatient_bed_movements:id,patient_id,admission_id,movement_type,source_bed_id,destination_bed_id,facility_id'],
  ward_and_bed_management: ['ward_units:id,name,code,facility_id', 'ward_beds:id,ward_id,bed_number,status,patient_id,admission_id,facility_id'],
  nursing_documentation: ['nursing_notes:id,patient_id,encounter_id,admission_id,author_id,note_type,note_text,facility_id', 'nursing_care_plans:id,patient_id,admission_id,problem,goal,status,created_by,facility_id', 'nursing_shift_handovers:id,patient_id,admission_id,clinical_summary,pending_tasks,safety_concerns,shift_label,facility_id'],
  emergency_care: ['emergency_cases:id,patient_id,arrival_time,acuity,status,facility_id'],
  operating_theatre: ['theatre_cases:id,patient_id,procedure_name,theatre_name,anesthetist_id,scheduled_start,urgency,status,facility_id', 'anesthetic_assessments:id,patient_id,encounter_id,asa_class,cleared_for_procedure,status,facility_id'],
  blood_transfusion: ['transfusion_records:id,patient_id,blood_group,component,unit_identifier,blood_product,reaction_observed,status,facility_id'],
  laboratory_orders_and_results: ['lab_orders:id,patient_id,encounter_id,ordered_by,test_name,status,lab_test_catalogue_id,facility_id', 'lab_results:id,lab_order_id,result_data,parameter_results,approved_by,approved_at,status,facility_id', 'lab_specimens:id,lab_order_id,accession_number,barcode_value,specimen_type,status', 'lab_test_catalogue:id,test_code,test_name,sample_quantity'],
  diagnostic_imaging: ['imaging_orders:id,patient_id,encounter_id,modality,study_name,status,requested_by,facility_id'],
  prescriptions_and_medicine_administration: ['prescriptions:id,patient_id,encounter_id,prescribed_by,medication,dosage,frequency,status,facility_id', 'medication_administrations:id,patient_id,prescription_id,medication_name,dose,route,scheduled_at,status,facility_id'],
  pharmacy_inventory_and_dispensing: ['pharmacy_inventory:id,drug_name,stock_quantity,reorder_level,expiry_date,facility_id', 'pharmacy_dispensing_plans:id,prescription_id,patient_id,inventory_id,computed_quantity,prepared_quantity,status,facility_id', 'pharmacy_pos_sales:id,patient_id,medication,inventory_id,quantity,total_amount,status,facility_id'],
  service_orders_and_billing: ['service_orders:id,patient_id,department,service_name,amount,status,order_type,service_code,invoice_id,facility_id', 'invoices:id,invoice_number,patient_id,encounter_id,total_amount,paid_amount,outstanding_amount,status,facility_id', 'invoice_items:id,invoice_id,description,quantity,unit_price,amount,service_order_id,facility_id', 'payments:id,invoice_id,patient_id,amount,method,status,facility_id'],
  insurance: ['insurance_claims:id,invoice_id,patient_id,amount_claimed,amount_approved,status,claim_number,facility_id', 'insurance_cases:id,patient_id,payer_name,policy_number,eligibility_status,claim_status,facility_id'],
  human_resources_and_payroll: ['hr_employees:id,facility_id,profile_id,employee_number,employment_status,start_date,base_salary', 'payroll_periods:id,facility_id,name,period_start,period_end,pay_date,status', 'payroll_items:id,payroll_period_id,employee_id,basic_pay,gross_pay,net_pay,status'],
  maternity_and_fertility: ['maternity_episodes:id,patient_id,facility_id', 'fertility_cycles:id,patient_id,cycle_type,start_date,status,facility_id'],
  specialist_clinics: ['dental_assessments:id,patient_id,encounter_id,facility_id,tooth_chart_data,created_by', 'ophthalmology_assessments:id,patient_id,encounter_id,facility_id,visual_acuity_left,visual_acuity_right', 'physio_assessments:id,patient_id,encounter_id,facility_id,assessment_type,treatment_plan', 'dietary_assessments:id,patient_id,encounter_id,facility_id,clinical_assessment,nutritional_diagnosis'],
  referrals_and_care_transitions: ['patient_referrals:id,patient_id,encounter_id,destination,specialty,reason,status,facility_id', 'care_transitions:id,patient_id,admission_id,transition_type,status,destination,summary,facility_id'],
  telemedicine: ['video_sessions:id,appointment_id,patient_id,practitioner_id,room_name,status,service_order_id,facility_id'],
  reporting_and_audit: ['report_definitions:id,report_code,report_name,extractor_key,implementation_status', 'report_generation_runs:id,facility_id,period_start,period_end,status', 'report_submissions:id,report_id,facility_id,period_start,period_end,status', 'system_audit_log:id,actor_id,action,module,entity_type,entity_id']
};

const failures = [];
let checkedTables = 0;
let checkedColumns = 0;
for (const [moduleName, entries] of Object.entries(moduleContracts)) {
  for (const entry of entries) {
    const [tableName, columnList] = entry.split(':');
    const expected = columnList.split(',');
    const actual = tables.get(tableName);
    if (!actual) {
      failures.push(`${moduleName}: missing generated table type ${tableName}`);
      continue;
    }
    checkedTables += 1;
    for (const column of expected) {
      checkedColumns += 1;
      if (!actual.has(column)) failures.push(`${moduleName}: ${tableName} is missing column ${column}`);
    }
  }
}

assert.deepEqual(failures, [], `module schema contract failed:\\n${failures.join('\\n')}`);
console.log(`Module schema contract passed: ${checkedTables} module tables and ${checkedColumns} required columns across ${Object.keys(moduleContracts).length} workflows; ${tables.size} generated table types available.`);
