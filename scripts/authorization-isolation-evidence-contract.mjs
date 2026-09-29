import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const file = path.join(root, "scripts", "authorization-isolation-evidence.json");
const data = JSON.parse(fs.readFileSync(file, "utf8"));

const fail = (message) => {
  console.error(`[authorization-isolation-evidence] FAIL: ${message}`);
  process.exitCode = 1;
};

if (data.version !== 1) fail("unsupported evidence schema version");
if (data.scope !== "isolated-cross-facility-regression") fail("invalid scope");
if (data.environment !== "not_configured" && data.environment !== "isolated") {
  fail("environment must be not_configured or isolated");
}
if (!["not_run", "reviewed", "enforced"].includes(data.status)) {
  fail("invalid evidence status");
}

const requiredIds = [
  "a-read-own-facility",
  "b-read-own-facility",
  "a-read-cross-facility",
  "b-read-cross-facility",
  "a-mutate-own-facility",
  "b-mutate-own-facility",
  "a-mutate-cross-facility",
  "b-mutate-cross-facility",
  "admin-cross-facility"
];
const cases = Array.isArray(data.required_cases) ? data.required_cases : [];
const observed = Array.isArray(data.evidence?.cases) ? data.evidence.cases : [];

for (const id of requiredIds) {
  if (!cases.some((item) => item.id === id)) fail(`missing required case: ${id}`);
}

if (data.status !== "not_run") {
  if (data.environment !== "isolated") fail("non-not_run evidence requires an isolated environment");
  if (!data.evidence?.run_id || !data.evidence?.executed_at || !data.evidence?.database_environment) {
    fail("reviewed/enforced evidence requires run metadata");
  }
  if (observed.length !== requiredIds.length) {
    fail("reviewed/enforced evidence must contain exactly all required case observations");
  }

  for (const id of requiredIds) {
    const row = observed.find((item) => item.id === id);
    const expected = cases.find((item) => item.id === id)?.expected;
    if (!row) fail(`missing observation: ${id}`);
    else if (row.observed !== expected) fail(`case ${id} observed=${row.observed} expected=${expected}`);
    else if (!row.evidence_ref) fail(`case ${id} is missing evidence_ref`);
  }
}

if (data.status === "enforced" && data.environment !== "isolated") {
  fail("enforced status is forbidden outside an isolated environment");
}

console.log(`[authorization-isolation-evidence] status=${data.status} environment=${data.environment} observed=${observed.length}/${requiredIds.length}`);
