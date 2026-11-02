#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";

const sql = fs.readFileSync(
  "supabase/migrations/20260930014000_clinical_facility_reconciliation_control_plane.sql",
  "utf8",
).toLowerCase();
const addPatientId = sql.indexOf("add column if not exists patient_id uuid");
const addUpdatedAt = sql.indexOf("add column if not exists updated_at timestamptz");
const firstPatientUse = sql.indexOf("d.patient_id");
assert.ok(addPatientId >= 0 && addPatientId < firstPatientUse, "diagnoses.patient_id must exist before facility reconciliation reads it");
assert.ok(addUpdatedAt >= 0, "diagnoses.updated_at compatibility column must be established");
assert.ok(sql.includes("set patient_id = e.patient_id"), "existing diagnosis rows must inherit patient lineage from their encounter");
assert.ok(sql.includes("where d.encounter_id = e.id"), "diagnosis patient lineage must use the canonical encounter relationship");
assert.ok(sql.includes("alter table public.diagnoses alter column updated_at set not null"), "diagnosis updated_at must be non-null after backfill");
console.log("[diagnosis-compatibility-columns] patient lineage and timestamp contract passed");
