#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export function auditSecurityBestPractices(projectRoot = process.cwd()) {
  const roots = ["supabase/migrations", "supabase/functions", "supabase/tests"];
  const files = [];

  function walk(dir) {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.(sql|mjs|ts|tsx)$/.test(entry.name)) files.push(full);
    }
  }

  for (const root of roots) walk(path.join(projectRoot, root));

  const findings = [];
  const sqlFiles = files.filter((file) => file.endsWith(".sql")).sort();
  const normalizedFiles = sqlFiles.map((file) =>
    fs.readFileSync(file, "utf8").toLowerCase().replace(/\s+/g, " "),
  );
  const normalizedSql = normalizedFiles.join(" ");

  for (const file of files) {
    const source = fs.readFileSync(file, "utf8");

    if (/\bauth\.role\s*\(/i.test(source)) {
      findings.push({
        file: path.relative(projectRoot, file),
        rule: "no-auth-role",
        detail: "Use policy TO clauses or explicit authorization helpers instead of deprecated auth.role().",
      });
    }

    // auth.users metadata may populate a profile, but must not authorize access.
    const policyBodies = source.match(
      /create\s+policy[\s\S]*?(?=create\s+policy|alter\s+table|create\s+(?:or\s+replace\s+)?function|$)/gi,
    ) ?? [];
    for (const policy of policyBodies) {
      if (/raw_user_meta_data|user_metadata/i.test(policy)
        && /using\s*\(|with\s+check\s*\(/i.test(policy)) {
        findings.push({
          file: path.relative(projectRoot, file),
          rule: "no-user-metadata-authz",
          detail: "Do not use user-editable metadata for authorization or RLS decisions.",
        });
      }
    }
  }

  // Split at each public function declaration before checking SECURITY DEFINER.
  // A broad regex across the whole SQL corpus can otherwise associate a later
  // function's SECURITY DEFINER clause with an earlier invoker function.
  const functionStarts = [
    ...normalizedSql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)\s*\(/gi),
  ];    const overridePattern = new RegExp(
      "alter\\s+function\\s+public\\." + functionName +
        "\\b[\\s\\S]*?set\\s+search_path\\s*=",
      "i",
    );
