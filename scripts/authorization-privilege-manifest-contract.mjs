import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root=process.cwd();
const privilegePath=path.join(root,"scripts","function-privilege-manifest.json");
const authPath=path.join(root,"scripts","authorization-high-risk-manifest.json");
assert.ok(fs.existsSync(privilegePath),"function privilege manifest must exist");
assert.ok(fs.existsSync(authPath),"high-risk authorization manifest must exist");

const privilege=JSON.parse(fs.readFileSync(privilegePath,"utf8"));
const auth=JSON.parse(fs.readFileSync(authPath,"utf8"));

assert.ok(Object.keys(privilege.functions ?? {}).length > 0,"privilege manifest must contain functions");
assert.ok(Object.keys(auth.functions ?? {}).length > 0,"authorization manifest must contain functions");
assert.ok(Array.isArray(auth.review_dimensions),"authorization review dimensions must be declared");
assert.ok(auth.review_dimensions.includes("explicit_execute_grant"),"authorization manifest must track explicit EXECUTE review");

for (const [name,spec] of Object.entries(privilege.functions)) {
  const reviewed=auth.functions[name];
  assert.ok(reviewed,`${name} must also exist in the high-risk authorization manifest`);
  assert.ok(["source_contract_reviewed","requires_isolated_regression"].includes(reviewed.status),`${name}: invalid authorization review status`);
  assert.equal(reviewed.mutation,true,`${name}: selected privilege RPCs must be mutation workflows`);
  assert.equal(reviewed.patient_scoped,true,`${name}: selected high-risk RPCs must be patient-scoped`);
  assert.equal(reviewed.requires_isolated_regression,true,`${name}: isolated regression must remain required`);
  assert.ok(Array.isArray(spec.allowed_execute_roles) && spec.allowed_execute_roles.length > 0,`${name}: execute role policy required`);
}

console.log("[authorization-privilege-manifest] privilege and high-risk authorization manifests reconciled");