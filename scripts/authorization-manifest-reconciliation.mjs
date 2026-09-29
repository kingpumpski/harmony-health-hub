import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root = process.cwd();
const readJson = (name) =>
  JSON.parse(fs.readFileSync(path.join(root, "scripts", name), "utf8"));

const highRisk = readJson("authorization-high-risk-manifest.json");
const patientFacility = readJson("patient-facility-boundary-manifest.json");
const definer = readJson("security-definer-review-manifest.json");

const highRiskNames = new Set(Object.keys(highRisk.functions ?? {}));
const patientNames = new Set(Object.keys(patientFacility.functions ?? {}));

for (const name of patientNames) {
  assert.ok(
    highRiskNames.has(name),
    `patient/facility function missing from high-risk authorization inventory: ${name}`,
  );
  const item = highRisk.functions[name];
  assert.equal(item.patient_scoped, true, `${name}: patient/facility function must be patient_scoped`);
  assert.equal(item.requires_isolated_regression, true, `${name}: patient/facility function must require isolated regression`);
}

for (const [name, item] of Object.entries(highRisk.functions ?? {})) {
  if (item.patient_scoped) {
    assert.ok(
      patientNames.has(name),
      `patient-scoped high-risk function missing from patient/facility manifest: ${name}`,
    );
  }
  if (item.requires_isolated_regression) {
    assert.equal(
      item.patient_scoped,
      true,
      `${name}: isolated regression is currently reserved for patient-scoped authorization boundaries`,
    );
  }
}

const requiredDefinerDimensions = new Set(definer.required_review_dimensions ?? []);
for (const dimension of highRisk.review_dimensions) {
  if (dimension === "read_path" || dimension === "mutation_path") continue;
  assert.ok(
    requiredDefinerDimensions.has(dimension),
    `SECURITY DEFINER review manifest missing high-risk dimension: ${dimension}`,
  );
}

const isolation = readJson("authorization-isolation-evidence.json");
for (const [name, item] of Object.entries(highRisk.functions ?? {})) {
  if (item.requires_isolated_regression) {
    assert.ok(
      ["not_run", "reviewed", "enforced"].includes(isolation.status),
      `${name}: invalid isolation evidence status`,
    );
    if (isolation.status !== "not_run") {
      assert.equal(
        isolation.environment,
        "isolated",
        `${name}: reviewed/enforced isolation requires an isolated environment`,
      );
    }
  }
}

assert.equal(
  patientFacility.status_policy.pending_tenancy_enforcement,
  "awaits isolated cross-facility fixture and regression",
);
assert.equal(
  patientFacility.status_policy.enforced,
  "requires helper call in every overload plus isolated cross-facility regression evidence",
);
assert.equal(
  definer.review.anonymous_security_definer_execute,
  "must_remain_zero",
);

console.log(
  `Authorization manifest reconciliation passed: ${highRiskNames.size} high-risk RPCs; ` +
  `${patientNames.size} patient/facility boundaries; ${requiredDefinerDimensions.size} SECURITY DEFINER review dimensions.`,
);
