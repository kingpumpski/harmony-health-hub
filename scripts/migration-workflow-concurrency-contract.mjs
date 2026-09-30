import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const file=path.join(process.cwd(),".github","workflows","supabase-migrations.yml");
assert.ok(fs.existsSync(file),"Supabase migration workflow must exist");
const source=fs.readFileSync(file,"utf8");
assert.match(source,/concurrency:\s+group:\s+supabase-production-migrations/,"production migration workflow must serialize runs");
assert.match(source,/cancel-in-progress:\s+false/,"production migration runs must never be auto-cancelled");
assert.match(source,/runs-on:\s+ubuntu-latest\s+timeout-minutes:\s+20/,"migration job must have a bounded execution timeout");
console.log("[migration-workflow-concurrency] serialization and timeout contract passed");
