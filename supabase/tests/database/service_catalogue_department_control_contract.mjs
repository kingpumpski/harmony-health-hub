import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/20260929103000_service_catalogue_department_control.sql','utf8');
const required=['CREATE OR REPLACE FUNCTION public.update_service_catalogue_item','current_user_has_catalogue_create_permission','You may modify services only for your department','record_system_audit','REVOKE ALL ON FUNCTION public.update_service_catalogue_item'];
const missing=required.filter(x=>!sql.includes(x));
if(missing.length){console.error('Service catalogue department-control contract failed:',missing);process.exitCode=1}else console.log('Service catalogue department-control contract: all invariants present');