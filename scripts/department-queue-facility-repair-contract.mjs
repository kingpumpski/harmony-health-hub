import fs from 'node:fs';
const file='supabase/migrations/20261127100000_fix_department_queue_facility_scope.sql';
const sql=fs.readFileSync(file,'utf8');
const n=sql.toLowerCase().replace(/\s+/g,'');
for(const token of [
 'q.facility_id=v_facility','so.facility_id=v_facility','p.facility_id=v_facility',
 'v_facilityisnullandnotv_platform_admin',
 "public.has_role(auth.uid(),'it_admin')","public.has_role(auth.uid(),'system_superuser')"
]) if(!n.includes(token.replace(/\s+/g,''))) throw new Error('Missing facility-scope invariant: '+token);
if(!sql.includes('RETURNS TABLE(')||!sql.includes('SECURITY DEFINER')||!sql.includes("SET search_path = ''")) throw new Error('RPC contract/security mode changed');
if(n.includes("public.has_role(auth.uid(),'admin')orpublic.has_role(auth.uid(),'it_admin')")) throw new Error('Facility admin must not be a platform bypass');
for(const role of ['lab_technician','radiologist','radiology_technician','pharmacist','accountant','canteen','front_desk','nurse','specialist_nurse','midwife'])
 if(!sql.includes("ur.role='"+role+"'")&&!sql.includes("ur.role IN ('"+role)) throw new Error('Missing role check '+role);
if(!sql.includes('REVOKE ALL ON FUNCTION public.get_department_queue(text,integer) FROM PUBLIC, anon;')||!sql.includes('GRANT EXECUTE ON FUNCTION public.get_department_queue(text,integer) TO authenticated;')) throw new Error('RPC ACL changed');
console.log('[department-queue-facility-repair] PASS: queue, service order, and patient facility lineage enforced; only explicit platform roles bypass facility scope.');
