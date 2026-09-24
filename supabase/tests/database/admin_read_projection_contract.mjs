import fs from 'node:fs';

const shift = fs.readFileSync('src/pages/admin/ShiftManagement.tsx', 'utf8');
const bulk = fs.readFileSync('src/pages/admin/BulkUpload.tsx', 'utf8');

const shiftProjection = "db.from('staff_shift_assignments').select('id,user_id,department,shift_label,starts_at,ends_at,active')";
const bulkProjection = "supabase.from('bulk_import_jobs').select('id,entity_type,file_name,total_rows,successful_rows,failed_rows,status,created_at')";

if (!shift.includes(shiftProjection)) throw new Error('Expected shift assignment projection missing');
if (!bulk.includes(bulkProjection)) throw new Error('Expected bulk import history projection missing');
if (shift.includes("db.from('staff_shift_assignments').select('*')")) throw new Error('Broad staff shift read remains');
if (bulk.includes("supabase.from('bulk_import_jobs').select('*')")) throw new Error('Broad bulk import history read remains');

console.log('Admin read projection contract passed');
