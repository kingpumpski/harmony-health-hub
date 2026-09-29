import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
const file=path.join(process.cwd(),"scripts","live-function-privilege-audit.sql");
assert.ok(fs.existsSync(file),"read-only function privilege audit SQL must exist");
const sql=fs.readFileSync(file,"utf8").toLowerCase().replace(/--.*$/gm,"");
for(const required of ["pg_proc","pg_namespace","has_function_privilege('anon'","has_function_privilege('authenticated'","p.prosecdef=true","p.proconfig","p.proacl"]) assert.ok(sql.includes(required),`audit must contain ${required}`);
assert.ok(!/\b(insert|update|delete|alter|create|drop|grant|revoke)\b/i.test(sql),"live function privilege audit must remain read-only");
console.log("[function-privilege-audit] read-only catalog audit contract passed");
