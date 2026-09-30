import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const workflowPath=path.join(process.cwd(),".github","workflows","supabase-migrations.yml");
assert.ok(fs.existsSync(workflowPath),"Supabase migration workflow must exist");
const source=fs.readFileSync(workflowPath,"utf8");

assert.match(source,/confirm_production_apply:/,"production migration confirmation input is required");
assert.match(source,/test "\$\{\{ inputs\.confirm_production_apply \}\}" = "APPLY_PRODUCTION"/,"apply mode must verify explicit production confirmation");
assert.match(source,/inputs\.mode == 'apply' && inputs\.confirm_production_apply == 'APPLY_PRODUCTION'/,"migration apply step must be gated by explicit confirmation");
assert.match(source,/supabase db push --linked/,"migration push command must remain explicit");
assert.match(source,/if: \$\{\{ inputs\.mode == 'validate' \}\}/,"validate mode must remain available without production confirmation");
assert.match(source,/if: \$\{\{ inputs\.mode == 'apply' \|\| inputs\.mode == 'verify' \}\}/,"post-apply verification must remain available");

console.log("[migration-workflow-safety] production apply confirmation contract passed");
