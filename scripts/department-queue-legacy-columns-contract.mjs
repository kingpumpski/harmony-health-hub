import assert from "node:assert/strict";
import fs from "node:fs";

const migration = fs.readFileSync("supabase/migrations/20260911233000_phase2_service_order_payment_gating.sql", "utf8");
const compatibility = fs.readFileSync("supabase/migrations/20260911241000_phase2_legacy_queue_compatibility.sql", "utf8");
const coverage = fs.readFileSync("supabase/migrations/20260914000000_patient_visit_coverage_activation.sql", "utf8");
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
const eventStart = coverage.indexOf("CREATE OR REPLACE FUNCTION public.service_order_event_trigger()");
const eventEnd = coverage.indexOf("\n$$;", eventStart);
assert.ok(eventStart >= 0 && eventEnd > eventStart, "coverage migration must define the service-order event trigger");
const eventFunction = coverage.slice(eventStart, eventEnd);
assert.match(eventFunction, /INSERT INTO public\.department_queues\s*\([\s\S]*?service_order_id,[\s\S]*?patient_id,[\s\S]*?department,[\s\S]*?priority,[\s\S]*?queued_at,[\s\S]*?status/i, "auto-released covered visits must populate legacy queue-required columns");
assert.match(eventFunction, /COALESCE\(NEW\.created_by, NEW\.requested_by, auth\.uid\(\)\)/i, "covered-visit queue rows must retain their creator");
assert.match(eventFunction, /ON CONFLICT \(service_order_id\) WHERE service_order_id IS NOT NULL DO NOTHING/i, "covered-visit queue insert must infer the partial unique index");
assert.doesNotMatch(eventFunction, /INSERT INTO public\.department_queues\s*\(service_order_id\s*,\s*department\s*\)/i, "covered-visit queue insert must not omit legacy required columns");
console.log("[department-queue-legacy-columns] migration ordering and covered-visit runtime contracts passed");
