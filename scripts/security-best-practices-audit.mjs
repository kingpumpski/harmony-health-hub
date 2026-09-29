#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

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

for (const root of roots) walk(path.join(process.cwd(), root));

const findings = [];

for (const file of files) {
  const source = fs.readFileSync(file, "utf8");

  if (/\bauth\.role\s*\(/i.test(source)) {
    findings.push({
      file,
      rule: "no-auth-role",
      detail: "Use policy TO clauses or explicit authorization helpers instead of deprecated auth.role().",
    });
  }

  if (/raw_user_meta_data|user_metadata/i.test(source) && /CREATE\s+POLICY|USING\s*\(|WITH\s+CHECK\s*\(/i.test(source)) {
    findings.push({
      file,
      rule: "no-user-metadata-authz",
      detail: "Do not use user-editable metadata for authorization or RLS decisions.",
    });
  }

  const publicDefiners = source.match(
    /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.[\s\S]*?SECURITY\s+DEFINER[\s\S]*?(?=CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION|$)/gi,
  ) ?? [];

  for (const block of publicDefiners) {
    if (!/SET\s+search_path\s*=/i.test(block)) {
      findings.push({
        file,
        rule: "security-definer-search-path",
        detail: "Every public SECURITY DEFINER function must explicitly set a safe search_path.",
      });
    }
  }

  const publicViews = source.match(/CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+public\.[^;]+/gis) ?? [];
  for (const view of publicViews) {
    if (!/security_invoker\s*=\s*true/i.test(view)) {
      findings.push({
        file,
        rule: "security-invoker-view",
        detail: "Public API-facing views should use security_invoker=true or be deliberately isolated/revoked.",
      });
    }
  }
}

if (findings.length) {
  console.error("Security best-practice audit failed:");
  for (const finding of findings) {
    console.error(`- [${finding.rule}] ${finding.file}: ${finding.detail}`);
  }
  process.exitCode = 1;
} else {
  console.log(`Security best-practice audit passed across ${files.length} source files.`);
}
