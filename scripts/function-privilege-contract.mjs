import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
const root=process.cwd();
const migrationsDir=path.join(root,"supabase","migrations");
const manifestPath=path.join(root,"scripts","function-privilege-manifest.json");
assert.ok(fs.existsSync(manifestPath),"function privilege manifest must exist");
const manifest=JSON.parse(fs.readFileSync(manifestPath,"utf8"));
assert.equal(manifest.version,1);
assert.equal(manifest.scope,"selected-high-risk-function-execute-contract");
const files=fs.existsSync(migrationsDir)?fs.readdirSync(migrationsDir).filter(n=>n.endsWith(".sql")):[];
const source=files.map(n=>fs.readFileSync(path.join(migrationsDir,n),"utf8")).join("\n").replace(/--.*$/gm,"");
const compact=(s)=>s.replace(/\s+/g,"").toLowerCase();
const sql=compact(source);
for(const [name,spec] of Object.entries(manifest.functions)){
 assert.ok(Array.isArray(spec.signatures)&&spec.signatures.length>0,`${name}: signatures required`);
 assert.deepEqual(spec.allowed_execute_roles,["authenticated"],`${name}: selected contract must remain authenticated-only`);
 const arities=declaredArities(name);
 assert.ok(arities.length>0,`${name}: function declaration must exist in migration history`);
 for(const signature of spec.signatures){
  assert.ok(arities.includes(signatureArity(signature)),`${name}: manifest signature ${signature} does not match any declared overload arity (${arities.join(",")})`);
  const qualified=`public.${name}(${signature})`;
  assert.ok(sql.includes(compact(`grant execute on function ${qualified} to authenticated;`)),`${qualified} must have an explicit authenticated EXECUTE grant`);
  if(spec.requires_public_revoke){
   assert.ok(sql.includes(compact(`revoke all on function ${qualified} from public;`))||sql.includes(compact(`revoke execute on function ${qualified} from public;`)),`${qualified} must explicitly revoke PUBLIC EXECUTE`);
  }
  if(spec.requires_anon_revoke){
   assert.ok(sql.includes(compact(`revoke all on function ${qualified} from public, anon;`))||sql.includes(compact(`revoke execute on function ${qualified} from anon;`))||sql.includes(compact(`revoke all on function ${qualified} from anon;`)),`${qualified} must explicitly revoke anon EXECUTE`);
  }
 }
}
console.log(`[function-privilege] checked ${Object.keys(manifest.functions).length} selected high-risk RPCs`);
