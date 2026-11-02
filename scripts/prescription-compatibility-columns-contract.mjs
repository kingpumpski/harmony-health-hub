#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";

const sql = fs.readFileSync(
  "supabase/migrations/20260930014000_clinical_facility_reconciliation_control_plane.sql",
  "utf8",
).toLowerCase();
const addMedication = sql.indexOf("add column if not exists medication_name text");
const addRoute = sql.indexOf("add column if not exists route text");
const addUpdated = sql.indexOf("add column if not exists updated_at timestamptz");
const firstMedicationUse = sql.indexOf("coalesce(rx.medication_name,rx.medication)");
assert.ok(addMedication >= 0 && addMedication < firstMedicationUse, "medication_name must exist before facility reconciliation reads it");
assert.ok(addRoute >= 0 && addUpdated >= 0, "prescription route and updated_at compatibility columns must be established");
assert.ok(sql.includes("coalesce(nullif(btrim(medication_name), ''), medication)"), "existing medication names must be preserved and missing values backfilled");
assert.ok(sql.includes("alter column updated_at set not null"), "prescription updated_at must be non-null after backfill");
console.log("[prescription-compatibility-columns] downstream prescription schema contract passed");
