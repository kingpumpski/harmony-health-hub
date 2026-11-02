import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const workflowPath = path.join(process.cwd(), ".github", "workflows", "supabase-migrations.yml");
assert.ok(fs.existsSync(workflowPath), "Supabase migration workflow must exist");
const source = fs.readFileSync(workflowPath, "utf8");

assert.match(source, /confirm_production_apply:/, "production migration confirmation input is required");
const modeInput = source.split("      mode:")[1]?.split("      confirm_production_apply:")[0] ?? "";
assert.match(modeInput, /type: choice[\\s\\S]*options:\\s*\\n\\s*- validate\\s*\\n\\s*- apply\\s*\\n\\s*- verify/, "migration modes must be choices");
const confirmationInput = source.split("      confirm_production_apply:")[1]?.split("\\npermissions:")[0] ?? "";
assert.doesNotMatch(confirmationInput, /options:/, "production confirmation must remain free text");
assert.match(source, /npm run test:migration-filename-uniqueness/, "migration filename uniqueness must be checked");
assert.match(source, /npm run test:production-migration-baseline-gate/, "baseline safety contract must run before remote operations");
assert.match(source, /production-migration-baseline-gate\\.mjs --mode apply/, "apply mode must pass the baseline gate");
assert.match(source, /test "\\$\\{\\{ inputs\\.confirm_production_apply \\}\\}" = "APPLY_PRODUCTION"/, "apply mode must require explicit production confirmation");
assert.match(source, /inputs\\.mode == 'apply' && inputs\\.confirm_production_apply == 'APPLY_PRODUCTION'/, "production push must require explicit confirmation");
assert.match(source, /supabase db push --linked\\n/, "the only production push must remain explicit and guarded");
assert.doesNotMatch(source, /supabase db push --linked --dry-run/, "do not dry-run an unreconciled historical chain against production");
assert.match(source, /production-migration-baseline-gate\\.mjs --mode validate/, "validate mode must report baseline block without pushing");
assert.match(source, /name: Reload PostgREST schema cache[\\s\\S]*supabase db query --linked "NOTIFY pgrst, 'reload schema';"/, "successful apply must reload PostgREST schema cache");
assert.match(source, /if: \\$\\{\\{ inputs\\.mode == 'apply' \\|\\| inputs\\.mode == 'verify' \\}\\}/, "post-apply verification must remain available");

console.log("[migration-workflow-safety] baseline-aware production migration workflow contract passed");
