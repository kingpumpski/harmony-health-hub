import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root = process.cwd();
const manifestPath = path.join(root, "scripts", "authorization-high-risk-manifest.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

assert.equal(manifest.version, 1, "unsupported high-risk manifest version");
assert.equal(manifest.scope, "high-risk-authorization-rpc-review");
assert.ok(Array.isArray(manifest.review_dimensions) && manifest.review_dimensions.length >= 8);
assert.deepEqual(
  new Set(manifest.status_vocabulary),
  new Set(["source_contract_reviewed", "requires_isolated_regression"]),
);

const roots = ["supabase/migrations", "supabase/functions", "supabase/tests"];
const sources = [];
function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (/\.(sql|mjs|ts|tsx)$/.test(entry.name)) sources.push(fs.readFileSync(full, "utf8"));
  }
}
for (const rootDir of roots) walk(path.join(root, rootDir));
const source = sources.join("\n");

function overloadCount(name) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    "CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\." +
      escaped + "\\s*\\([^)]*\\)",
    "gi",
  );
  return [...source.matchAll(pattern)].length;
}

const functions = manifest.functions ?? {};
assert.ok(Object.keys(functions).length >= 9, "high-risk inventory is unexpectedly small");

for (const [name, item] of Object.entries(functions)) {
  assert.ok(overloadCount(name) > 0, `high-risk function missing from repository: ${name}`);
  assert.ok(manifest.status_vocabulary.includes(item.status), `${name}: invalid review status`);
  assert.equal(typeof item.patient_scoped, "boolean", `${name}: patient_scoped must be boolean`);
  assert.equal(typeof item.mutation, "boolean", `${name}: mutation must be boolean`);
  if (item.patient_scoped) {
    assert.equal(item.requires_isolated_regression, true, `${name}: patient-scoped function must require isolated regression`);
  }
}

const isolation = JSON.parse(
  fs.readFileSync(path.join(root, "scripts", "authorization-isolation-evidence.json"), "utf8"),
);
for (const [name, item] of Object.entries(functions)) {
  if (item.requires_isolated_regression) {
    assert.equal(
      isolation.status,
      "not_run",
      `${name}: isolated regression evidence must remain explicitly not_run until fixtures exist`,
    );
  }
}

console.log(
  `High-risk authorization manifest passed: ${Object.keys(functions).length} RPCs inventoried; ` +
  `${Object.values(functions).filter((item) => item.requires_isolated_regression).length} require isolated regression.`,
);
