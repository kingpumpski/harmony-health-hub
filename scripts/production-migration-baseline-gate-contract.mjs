import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const state = JSON.parse(fs.readFileSync(path.join(root, "supabase", "production-migration-baseline.json"), "utf8"));
const gate = fs.readFileSync(path.join(root, "scripts", "production-migration-baseline-gate.mjs"), "utf8");
const workflow = fs.readFileSync(path.join(root, ".github", "workflows", "supabase-migrations.yml"), "utf8");

assert.equal(state.status, "unreconciled", "production baseline must remain blocked until evidence-based reconciliation is approved");
assert.equal(state.productionPushAllowed, false, "production push must remain disabled");
assert.ok(state.knownBaseline.some((item) => item.version === "20260916002251" && item.sqlRecovered === false));
assert.ok(state.knownBaseline.some((item) => item.version === "20260916003113" && item.sqlRecovered === false));
assert.match(gate, /mode === "apply" && !verified/, "apply mode must fail closed when baseline is unresolved");
assert.match(gate, /mode === "validate" && !verified/, "validate mode must not misrepresent unresolved production history as a normal dry-run");
assert.match(workflow, /production-migration-baseline-gate\.mjs --mode apply/, "production apply workflow must invoke baseline gate");
assert.doesNotMatch(workflow, /supabase db push --linked --dry-run/, "workflow must not dry-run an unreconciled historical chain against production");
console.log("[production-migration-baseline-gate] fail-closed contract passed");
