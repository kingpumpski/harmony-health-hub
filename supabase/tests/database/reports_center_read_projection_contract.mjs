import fs from 'node:fs';

const source = fs.readFileSync('src/lib/reportsCenter.ts', 'utf8');

if (source.includes(".select('*')")) throw new Error('Broad Reports Center select(*) remains');

const required = [
  "report_generation_items').select('id,run_id,report_id,status,output_format,file_name,data_snapshot,validation_messages,error_message,started_at,completed_at,created_at)",
  "report_generation_runs').select('id,facility_id,period_start,period_end,frequency,status,total_reports,success_count,warning_count,failed_count,created_at,completed_at)",
  "report_submissions').select('id,report_id,facility_id,period_start,period_end,due_date,status,submitted_at,submitted_by,submission_reference)"
];

for (const projection of required) {
  if (!source.includes(projection)) throw new Error('Required Reports Center projection missing: ' + projection);
}

const catalogueRequired = [
  "report_definitions').select('id,report_code,report_name,category_id,description,frequency,parameters,default_parameters,extractor_key,supported_formats,submission_deadline_day,is_active,implementation_status,report_categories(id,name,display_order)",
  "facility_report_config').select('id,facility_id,report_id,is_enabled,submission_deadline_day,custom_parameters,report_definitions(id,report_code,report_name,category_id,description,frequency,parameters,default_parameters,extractor_key,supported_formats,submission_deadline_day,is_active,implementation_status,report_categories(id,name,display_order)"
];
for (const projection of catalogueRequired) {
  if (!source.includes(projection)) throw new Error('Required Reports Center catalogue projection missing');
}
console.log('Reports Center read projection contract passed');
