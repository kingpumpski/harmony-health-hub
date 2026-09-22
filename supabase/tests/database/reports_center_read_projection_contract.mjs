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

console.log('Reports Center read projection contract passed');
