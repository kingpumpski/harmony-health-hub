#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const dir=path.join(process.cwd(),"supabase","migrations");
const baseline="20260929214500_reconcile_revoked_role_helper_rls_policies.sql";
const helpers=[
  "current_user_has_role\\s*\\(",
  "current_user_is_clinical_staff\\s*\\(",
  "current_user_can_edit_patient_record\\s*\\("
];
const files=fs.readdirSync(dir).filter(n=>n.endsWith(".sql") && n>=baseline).sort();
const failures=[];
for(const name of files){
  const source=fs.readFileSync(path.join(dir,name),"utf8").replace(/--.*$/gm,"");
  const policies=[...source.matchAll(/(?:CREATE|ALTER)\\s+POLICY[\\s\\S]*?(?=(?:CREATE|ALTER)\\s+POLICY|$)/gi)];
  for(const match of policies){
    for(const helper of helpers){
      const direct=new RegExp("(?<!\\(select\\s+)public\\."+helper,"i");
      if(direct.test(match[0])){
        failures.push(name+": RLS policy must wrap stable no-arg authorization helper in (select ...): "+helper);
      }
    }
  }
}
assert.equal(failures.length,0,"RLS helper performance contract failed:\\n"+failures.join("\\n"));
console.log("RLS helper performance contract passed for "+files.length+" post-baseline migrations.");
