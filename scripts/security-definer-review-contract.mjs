#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root=process.cwd();
const files=[];
function walk(dir){if(!fs.existsSync(dir))return;for(const e of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,e.name);if(e.isDirectory())walk(p);else if(/\\.(sql|mjs|ts|tsx)$/.test(e.name))files.push(p);}}
for(const d of ["supabase/migrations","supabase/functions","supabase/tests"])walk(path.join(root,d));
const source=files.map(f=>fs.readFileSync(f,"utf8")).join("\n");

assert(!/auth\\.role\\s*\\(/i.test(source),"deprecated auth.role() detected");
assert(!/(raw_user_meta_data|user_metadata)/i.test(source.match(/create\\s+policy[\\s\\S]{0,3000}/ig)?.join("\n")??""),"user-editable metadata appears in policy source");

const defs=[...source.matchAll(/create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.[\\s\\S]*?\\bsecurity\\s+definer\\b[\\s\\S]*?(?=create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.|$)/ig)].map(m=>m[0]);
for(const def of defs){
  assert(/set\\s+search_path\\s+to\\s+/i.test(def),"SECURITY DEFINER function lacks explicit search_path");
  assert(!/set\\s+search_path\\s+to\\s+['"]?public\\b/i.test(def),"SECURITY DEFINER function places public first as search_path");
}
const manifest=JSON.parse(fs.readFileSync(path.join(root,"scripts","security-definer-review-manifest.json"),"utf8"));
assert.equal(manifest.version,1);
assert.equal(manifest.review.authenticated_security_definer_lint,"accepted_pending_function_specific_review");
assert.match(manifest.review.anonymous_security_definer_execute,/zero/i);
console.log(`SECURITY DEFINER source contract passed: ${defs.length} public definitions have explicit search_path configuration and no deprecated auth.role() usage was detected.`);
