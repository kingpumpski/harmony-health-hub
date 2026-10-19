import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const workflowPath=path.join(process.cwd(),".github","workflows","supabase-migrations.yml");
assert.ok(fs.existsSync(workflowPath),"Supabase migration workflow must exist");
const source=fs.readFileSync(workflowPath,"utf8");

assert.match(source,/confirm_production_apply:/,"production migration confirmation input is required");
const modeInput = source.split('      mode:')[1]?.split('      confirm_production_apply:')[0] ?? '';
assert.match(modeInput, /type: choice[\s\S]*options:\s*\n\s*- validate\s*\n\s*- apply\s*\n\s*- verify/, 'migration modes must be choices on the mode input');
const confirmationInput = source.split('      confirm_production_apply:')[1]?.split('\npermissions:')[0] ?? '';
assert.doesNotMatch(confirmationInput, /options:/, 'production confirmation must remain free text');
assert.match(source, /npm run test:migration-filename-uniqueness/, 'migration execution must reject duplicate versions before linking');
assert.match(source,/test "\$\{\{ inputs\.confirm_production_apply \}\}" = "APPLY_PRODUCTION"/,"apply mode must verify explicit production confirmation");
assert.match(source,/inputs\.mode == 'apply' && inputs\.confirm_production_apply == 'APPLY_PRODUCTION'/,"migration apply step must be gated by explicit confirmation");
assert.match(source,/supabase db push --linked/,"migration push command must remain explicit");
assert.match(source,/name: Reload PostgREST schema cache[\s\S]*supabase db query --linked "NOTIFY pgrst, 'reload schema';"/,"successful production migration apply must reload the PostgREST schema cache");
assert.match(source,/if: \$\{\{ inputs\.mode == 'validate' \}\}/,"validate mode must remain available without production confirmation");
assert.match(source,/if: \$\{\{ inputs\.mode == 'apply' \|\| inputs\.mode == 'verify' \}\}/,"post-apply verification must remain available");

console.log("[migration-workflow-safety] production apply confirmation contract passed");
