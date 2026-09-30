#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root = process.cwd();
const files = [];

function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (/\.(sql|mjs|ts|tsx)$/.test(entry.name)) files.push(full);
  }
}

for (const dir of ["supabase/migrations", "supabase/functions", "supabase/tests"]) {
  walk(path.join(root, dir));
}

const sources = files.map((file) => ({
  file,
  source: fs.readFileSync(file, "utf8"),
}));

const combined = sources.map(({ source }) => source).join("\n");

assert(
  !/\bauth\.role\s*\(/i.test(combined),
  "deprecated auth.role() detected",
);

for (const { file, source } of sources) {
  if (
    /raw_user_meta_data|user_metadata/i.test(source) &&
    /CREATE\s+POLICY|USING\s*\(|WITH\s+CHECK\s*\(/i.test(source)
  ) {
    assert.fail(
      `user-editable metadata appears in authorization/policy source: ${file}`,
    );
  }
}

const publicDefinerPattern =
  /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.[\s\S]*?\bSECURITY\s+DEFINER\b[\s\S]*?(?=CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.|$)/gi;

const defs = [];
for (const { file, source } of sources) {
  for (const match of source.matchAll(publicDefinerPattern)) {
    defs.push({ file, definition: match[0] });
  }
}

for (const { file, definition } of defs) {
  assert(
    /SET\s+search_path\s*=\s*/i.test(definition),
    `SECURITY DEFINER function lacks explicit search_path: ${file}`,
  );
  assert(
    !/SET\s+search_path\s*=\s*['"]?public\b/i.test(definition),
    `SECURITY DEFINER function places public first as search_path: ${file}`,
  );
}

const manifest = JSON.parse(
  fs.readFileSync(
    path.join(root, "scripts", "security-definer-review-manifest.json"),
    "utf8",
  ),
);

assert.equal(manifest.version, 1);
assert.equal(
  manifest.review.authenticated_security_definer_lint,
  "accepted_pending_function_specific_review",
);
assert.match(manifest.review.anonymous_security_definer_execute, /zero/i);
assert.match(manifest.review.search_path, /explicit/i);

console.log(
  `SECURITY DEFINER source contract passed: ${defs.length} public definitions have explicit safe search_path configuration and no deprecated auth.role() usage was detected across ${files.length} source files.`,
);
