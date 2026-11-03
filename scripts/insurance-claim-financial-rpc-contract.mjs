import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const migrationPath = path.join(root, "supabase", "migrations", "20260920062000_insurance_claim_financial_bounds.sql");
const migration = fs.readFileSync(migrationPath, "utf8");
const caller = fs.readFileSync(path.join(root, "src", "pages", "InsuranceClaims.tsx"), "utf8");

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.update_insurance_claim_financials\s*\(/i);
assert.match(migration, /\)\s*RETURNS public\.insurance_claims\b/i, "the established composite return type must remain unchanged");
assert.match(migration, /AS \$claim_financials\$/i, "the function must open with the tagged delimiter");
assert.match(migration, /RETURN c;\s*END;\s*\$claim_financials\$;/i, "the function must close with the identical delimiter and return its row");
assert.match(migration, /REVOKE ALL ON FUNCTION public\.update_insurance_claim_financials/i);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.update_insurance_claim_financials[\s\S]*TO authenticated/i);
assert.match(caller, /rpc\(['"]update_insurance_claim_financials['"]/i, "the claims UI RPC caller must remain present");

console.log("[insurance-claim-financial-rpc] return-type and tagged-delimiter contract passed");
