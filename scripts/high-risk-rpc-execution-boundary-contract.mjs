#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";

const source = fs.readFileSync(
  "supabase/migrations/20260930012001_harden_high_risk_rpc_execution_boundaries.sql",
  "utf8",
);
const sql = source.replace(/\s+/g, " ").trim().toLowerCase();
const signatures = [
  "public.create_ai_clinical_session(uuid,text,jsonb,jsonb)",
  "public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric)",
  "public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric)",
  "public.create_insurance_claim_draft(uuid,text,text,numeric,uuid)",
  "public.create_pharmacy_pos_sale(uuid,uuid,integer)",
  "public.update_patient_workflow(uuid,jsonb)",
  "public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text)",
  "public.search_patient_directory(text,integer)",
];
for (const signature of signatures) {
  assert.ok(sql.includes("('" + signature + "')"), "missing guarded RPC signature: " + signature);
}
assert.ok(sql.includes("do $high_risk_rpc_execution_boundaries$"), "missing guarded execution boundary block");
assert.ok(sql.includes("pg_catalog.to_regprocedure(v_signature)"), "function existence must be checked by exact signature");
assert.ok(sql.includes("p.proconfig"), "existing function search_path must be inspected");
assert.ok(sql.includes("not coalesce(v_config @> array['search_path=\"\"']"), "empty search_path must be preserved");
assert.ok(sql.includes("format( 'alter function %s set search_path = pg_catalog, public', v_function )"), "existing functions must receive pinned search_path");
assert.ok(sql.includes("format( 'revoke all on function %s from public, anon', v_function )"), "existing functions must deny PUBLIC and anon");
assert.ok(sql.includes("format( 'grant execute on function %s to authenticated', v_function )"), "existing functions must retain authenticated RPC execution");
assert.ok(sql.includes("notify pgrst, 'reload schema'"), "PostgREST schema cache reload must remain");
console.log("[high-risk-rpc-execution-boundary] guarded signature and privilege contract passed");
