import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { auditSecurityBestPractices } from "./security-best-practices-audit.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "harmony-security-audit-"));
const migrations = path.join(root, "supabase/migrations");
const functions = path.join(root, "supabase/functions");
fs.mkdirSync(migrations, { recursive: true });
fs.mkdirSync(functions, { recursive: true });
const write = (name, source) => fs.writeFileSync(path.join(migrations, name), source);

try {
  write("20260101000000_functions.sql", `
    CREATE FUNCTION public.invoker_rpc() RETURNS text
    LANGUAGE sql AS $ SELECT 'invoker'; $;
    CREATE FUNCTION public.unsafe_rpc() RETURNS text
    LANGUAGE sql SECURITY DEFINER AS $$ SELECT 'unsafe'; $$;
    CREATE FUNCTION public.safe_rpc() RETURNS text
    LANGUAGE sql SECURITY DEFINER SET search_path = ''
    AS $ SELECT 'safe'; $;
    CREATE FUNCTION public.safe_to_rpc() RETURNS text
    LANGUAGE sql SECURITY DEFINER SET search_path TO ''
    AS $ SELECT 'safe'; $;
    CREATE FUNCTION public.later_secured_rpc() RETURNS text
    LANGUAGE sql SECURITY DEFINER AS $$ SELECT 'later'; $$;
    ALTER FUNCTION public.later_secured_rpc() SET search_path = '';
  `);
  write("20260101000001_policy.sql", `
    CREATE POLICY metadata_policy ON public.example
    USING ((auth.jwt() -> 'user_metadata' ->> 'is_admin') = 'true');
  `);
  fs.writeFileSync(path.join(functions, "legacy.ts"), "const role = auth.role();");

  let result = auditSecurityBestPractices(root);
  assert.ok(result.findings.some(f => f.rule === "security-definer-search-path" && f.file.endsWith("20260101000000_functions.sql") && f.functionName === "unsafe_rpc"), "missing SECURITY DEFINER search_path must be attributed to its exact function and source file");
  assert.ok(result.findings.some(f => f.rule === "no-user-metadata-authz"), "user metadata in RLS policy must be detected");
  assert.ok(result.findings.some(f => f.rule === "no-auth-role"), "deprecated auth.role usage must be detected");
  assert.equal(result.findings.filter(f => f.rule === "security-definer-search-path").length, 1, "inline and later ALTER FUNCTION search_path protections must pass");

  write("20260101000002_repair.sql", "ALTER FUNCTION public.unsafe_rpc() SET search_path = '';");
  result = auditSecurityBestPractices(root);
  assert.equal(result.findings.filter(f => f.rule === "security-definer-search-path").length, 0, "a later ALTER FUNCTION must repair the effective definition");

  fs.rmSync(path.join(functions, "legacy.ts"));
  result = auditSecurityBestPractices(root);
  assert.equal(result.findings.filter(f => f.rule === "no-auth-role").length, 0, "removing deprecated auth.role source must clear that finding");
  console.log("[security-best-practices-audit-regression] SECURITY DEFINER search_path, later overrides, deprecated auth.role and metadata-policy checks passed");
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
