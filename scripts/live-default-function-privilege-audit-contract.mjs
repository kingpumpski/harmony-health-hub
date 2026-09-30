import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
const file=path.join(process.cwd(),"scripts","live-default-function-privilege-audit.sql");
assert.ok(fs.existsSync(file),"default function privilege audit SQL must exist");
const sql=fs.readFileSync(file,"utf8").toLowerCase().replace(/--.*$/gm,"");
for(const required of ["pg_default_acl","pg_roles","defaclobjtype","defaclacl","r.rolname='postgres'","d.defaclobjtype='f'"]) assert.ok(sql.includes(required),`default privilege audit must contain ${required}`);
assert.ok(!/\b(insert|update|delete|alter|create|drop|grant|revoke)\b/i.test(sql),"default privilege audit must remain read-only");
console.log("[default-privilege-audit] read-only catalog audit contract passed");
