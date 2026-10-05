import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const file=path.join(process.cwd(),"scripts","live-test-mode-privilege-audit.sql");
assert.ok(fs.existsSync(file),"test-mode privilege audit SQL must exist");
const sql=fs.readFileSync(file,"utf8").toLowerCase().replace(/--.*$/gm,"");
for (const required of [
  "hms_test_runtime",
  "hms_test_users",
  "hms_test_runtime_audit",
  "has_table_privilege('anon'",
  "has_table_privilege('authenticated'",
  "c.relrowsecurity"
]) assert.ok(sql.includes(required),`audit must contain ${required}`);
assert.ok(!/\b(insert|update|delete|alter|create|drop|grant|revoke)\b/i.test(sql),"live test-mode privilege audit must remain read-only");
console.log("[test-mode-privilege-audit] read-only control-plane privilege contract passed");
