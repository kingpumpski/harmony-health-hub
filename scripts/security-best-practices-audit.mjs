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

const sqlFiles = files.filter((file) => file.endsWith(".sql")).sort();
const sqlSource = sqlFiles.map((file) => fs.readFileSync(file, "utf8")).join("\n");
const normalizedSql = sqlSource.toLowerCase();

for (const file of files) {
  const source = fs.readFileSync(file, "utf8");

  if (/\bauth\.role\s*\(/i.test(source)) {
    findings.push({
      file,
      rule: "no-auth-role",
      detail: "Use policy TO clauses or explicit authorization helpers instead of deprecated auth.role().",
    });
  }

  // auth.users metadata may be used to populate a profile, but must not be
  // used as an authorization/RLS decision. Only inspect actual policy bodies.
  const policyBodies = source.match(
    /create\s+policy[\s\S]*?(?=create\s+policy|alter\s+table|create\s+(?:or\s+replace\s+)?function|$)/gi,
  ) ?? [];
  for (const policy of policyBodies) {
    if (
      /raw_user_meta_data|user_metadata/i.test(policy) &&
      /using\s*\(|with\s+check\s*\(/i.test(policy)
    ) {
      findings.push({
        file,
        rule: "no-user-metadata-authz",
        detail: "Do not use user-editable metadata for authorization or RLS decisions.",
      });
    }
  }
}

// Audit the effective migration state, not every historical snapshot. A later
// CREATE OR REPLACE FUNCTION or ALTER FUNCTION supersedes an earlier declaration.
const definitions = [
  ...normalizedSql.matchAll(
    /create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.([a-z0-9_]+)\\s*\\([\\s\\S]*?\\)\\s*returns[\\s\\S]*?security\\s+definer/gi,
  ),
];

const latestDefinitions = new Map();
for (const match of definitions) {
  latestDefinitions.set(match[1], match);
}

for (const [functionName, match] of latestDefinitions) {
  const definitionIndex = match.index ?? 0;
  const remainder = normalizedSql.slice(definitionIndex);
  const nextFunction = remainder.search(
    /create\\s+(?:or\\s+replace\\s+)?function\\s+public\\./i,
  );
  const block = nextFunction > 0 ? remainder.slice(0, nextFunction) : remainder;
  const hasInlineSearchPath = /set\\s+search_path\\s*=/i.test(block);
  const overridePattern = new RegExp(
    "alter\\\\s+function\\\\s+public\\\\." + functionName +
      "\\\\b[\\\\s\\\\S]*?set\\\\s+search_path\\\\s*=",
    "i",
  );
  const hasLaterOverride = overridePattern.test(normalizedSql.slice(definitionIndex));
  if (!hasInlineSearchPath && !hasLaterOverride) {
    const sourceFile = sqlFiles.find((file) => {
      const text = fs.readFileSync(file, "utf8").toLowerCase();
      return text.includes("create or replace function public." + functionName) ||
        text.includes("create function public." + functionName);
    }) ?? "supabase/migrations";
    findings.push({
      file: sourceFile,
      rule: "security-definer-search-path",
      detail: "Every effective public SECURITY DEFINER function must explicitly set a safe search_path.",
    });
  }
}

// Public view exposure is validated by the dedicated repository-wide
// public-view-security contract, which also handles revocation declared
// in a later migration. Keep this audit focused on function/authz rules.

if (findings.length) {
  console.error("Security best-practice audit failed:");
  for (const finding of findings) {
    console.error(`- [${finding.rule}] ${finding.file}: ${finding.detail}`);
  }
  process.exitCode = 1;
} else {
  console.log(`Security best-practice audit passed across ${files.length} source files.`);
}
