import assert from "node:assert/strict";
import fs from "node:fs";

const migration = fs.readFileSync("supabase/migrations/20260911233000_phase2_service_order_payment_gating.sql", "utf8");
const compatibility = fs.readFileSync("supabase/migrations/20260911241000_phase2_legacy_queue_compatibility.sql", "utf8");
const tableBlock = migration.indexOf("CREATE TABLE IF NOT EXISTS public.department_queues");
const columnRepair = migration.indexOf("ALTER TABLE public.department_queues", tableBlock);
const indexCreation = migration.indexOf("CREATE INDEX IF NOT EXISTS idx_department_queues_work", tableBlock);
assert.ok(tableBlock >= 0 && columnRepair > tableBlock && indexCreation > columnRepair, "legacy queue columns must be reconciled after CREATE TABLE IF NOT EXISTS and before the queue index");
const repairBlock = migration.slice(columnRepair, indexCreation);
for (const column of ["service_order_id", "queued_at", "claimed_by", "claimed_at"]) {
  assert.match(repairBlock, new RegExp("ADD COLUMN IF NOT EXISTS " + column + "\\b"), column + " must be added before use");
}
assert.match(repairBlock, /SET queued_at = COALESCE\(queued_at, created_at\)/, "legacy queue timestamps must be backfilled");
assert.match(repairBlock, /ALTER COLUMN queued_at SET NOT NULL/, "queue timestamp must be non-null before index creation");
assert.match(compatibility, /CREATE OR REPLACE FUNCTION public\.release_service_order/, "later compatibility migration must retain legacy required-column population");
console.log("[department-queue-legacy-columns] migration ordering contract passed");
