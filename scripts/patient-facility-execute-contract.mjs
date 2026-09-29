import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const file=path.join(process.cwd(),"supabase/migrations/20260929160000_patient_facility_tenancy_foundation.sql");
assert.ok(fs.existsSync(file),"patient/facility tenancy migration must exist");
const sql=fs.readFileSync(file,"utf8").replace(/--.*$/gm,"");

const functions=[
  ["hms_current_active_facility_id","()"],
  ["hms_patient_has_facility_access","(uuid)"],
  ["hms_assert_patient_facility_access","(uuid)"],
  ["link_patient_to_current_facility","(uuid, text)"],
  ["auto_link_patient_to_active_facility","()"],
];

for (const [name,args] of functions) {
  const escaped=name.replace(/[.*+?^$()|[\]\\]/g,"\\$&");
  assert.match(sql,new RegExp("REVOKE ALL ON FUNCTION public\\."+escaped+"\\("+args.replace(/[()]/g,"\\$&")+"\\) FROM PUBLIC","i"),name+" must revoke PUBLIC EXECUTE");
  assert.match(sql,new RegExp("REVOKE ALL ON FUNCTION public\\."+escaped+"\\("+args.replace(/[()]/g,"\\$&")+"\\) FROM anon","i"),name+" must explicitly revoke anon EXECUTE");
}

assert.match(sql,/GRANT EXECUTE ON FUNCTION public.hms_patient_has_facility_access(uuid) TO authenticated/i);
assert.match(sql,/GRANT EXECUTE ON FUNCTION public.hms_assert_patient_facility_access(uuid) TO authenticated/i);
assert.match(sql,/GRANT EXECUTE ON FUNCTION public.link_patient_to_current_facility(uuid, text) TO authenticated/i);

console.log("[patient-facility-execute] tenancy helper EXECUTE boundaries are explicit and anon-denied");
