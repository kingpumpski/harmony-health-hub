import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const gateSource = fs.readFileSync(path.join(repoRoot, "scripts", "production-migration-baseline-gate.mjs"), "utf8");
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "migration-baseline-gate-"));
const gateDir = path.join(tempRoot, "scripts");
const stateDir = path.join(tempRoot, "supabase");
const docsDir = path.join(tempRoot, "docs");
fs.mkdirSync(gateDir, { recursive: true });
fs.mkdirSync(stateDir, { recursive: true });
fs.mkdirSync(docsDir, { recursive: true });
const gatePath = path.join(gateDir, "production-migration-baseline-gate.mjs");
const statePath = path.join(stateDir, "production-migration-baseline.json");
const artifactPath = path.join(docsDir, "PRODUCTION_MIGRATION_PROVENANCE.md");
fs.writeFileSync(gatePath, gateSource);
fs.writeFileSync(artifactPath, "Reviewed migration provenance fixture for gate tests.\n");

const baseState = {
  schemaVersion: 1,
  projectRef: "ygqoptvezotdqhtimdkr",
  status: "unreconciled",
  productionPushAllowed: false,
  knownBaseline: [
    { version: "20260916002251", name: "canonical_remote_schema", sqlRecovered: false, mappingStatus: "unverified", mappedTo: null, mappingEvidence: null },
    { version: "20260916003113", name: "fix_start_imaging_order_queue_contract", sqlRecovered: false, mappingStatus: "unverified", mappedTo: null, mappingEvidence: null }
  ],
  verification: { verifiedAt: null, reviewedCommit: null, mappingArtifact: null, approvedBy: null },
  approvedPendingVersions: []
};
const writeState = (state) => fs.writeFileSync(statePath, JSON.stringify(state, null, 2));
const run = (mode, history) => {
  const args = [gatePath, "--mode", mode];
  if (history) args.push("--history-file", history);
  return spawnSync(process.execPath, args, { cwd: tempRoot, encoding: "utf8" });
};

try {
  writeState(baseState);
  assert.equal(run("validate").status, 2, "unreconciled validate must fail as blocked, not pass green");
  assert.equal(run("apply").status, 1, "unreconciled apply must fail closed");
  assert.equal(run("verify").status, 0, "read-only verify may run while baseline is unresolved");

  const historyPath = path.join(tempRoot, "history.txt");
  const verifiedState = {
    ...baseState,
    status: "verified",
    productionPushAllowed: true,
    knownBaseline: baseState.knownBaseline.map((entry) => ({
      ...entry,
      mappingStatus: "verified",
      mappedTo: "canonical_remote_schema",
      mappingEvidence: "sha256:reviewed-fixture"
    })),
    verification: {
      verifiedAt: "2026-11-03T00:00:00Z",
      reviewedCommit: "0123456789012345678901234567890123456789",
      mappingArtifact: "docs/PRODUCTION_MIGRATION_PROVENANCE.md",
      approvedBy: "reviewed-approval"
    },
    approvedPendingVersions: ["20261103000000"]
  };
  writeState({ ...verifiedState, verification: { ...verifiedState.verification, mappingArtifact: "docs/missing.md" } });
  assert.equal(run("validate", historyPath).status, 2, "missing mapping artifact must keep the baseline unverified");

  writeState({ ...verifiedState, verification: { ...verifiedState.verification, reviewedCommit: "not-a-commit" } });
  assert.equal(run("apply", historyPath).status, 1, "invalid reviewed commit must block apply");

  writeState(verifiedState);
  fs.writeFileSync(historyPath, "Local | Remote | Time (UTC)\n20261103000000 | | 2026-11-03\n");
  assert.equal(run("validate", historyPath).status, 0, "exact reviewed pending allowlist must pass history precheck");
  assert.equal(run("apply", historyPath).status, 0, "exact reviewed pending allowlist must pass apply precheck");

  fs.writeFileSync(historyPath, "Local | Remote | Time (UTC)\n20261103000001 | | 2026-11-03\n");
  assert.equal(run("apply", historyPath).status, 1, "unexpected pending version must block apply");

  fs.writeFileSync(historyPath, "Local | Remote | Time (UTC)\n20261103000000 | 20261103000002 | 2026-11-03\n");
  assert.equal(run("apply", historyPath).status, 1, "ambiguous local/remote version row must block apply");

  fs.writeFileSync(historyPath, "Local | Remote | Time (UTC)\n20261103000000 | | 2026-11-03\n20261103000000 | | 2026-11-03\n");
  assert.equal(run("apply", historyPath).status, 1, "duplicate local pending version must block apply");

  fs.writeFileSync(historyPath, "Local | Remote | Time (UTC)\n20261103000000 | 20261103000000 | 2026-11-03\n20261103000000 | 20261103000000 | 2026-11-03\n");
  assert.equal(run("apply", historyPath).status, 1, "duplicate remote migration version must block apply");

  fs.writeFileSync(historyPath, "Local | Remote | Time (UTC)\n2026110300000 | | 2026-11-03\n");
  assert.equal(run("apply", historyPath).status, 1, "malformed local migration version must block apply");

  writeState({ ...verifiedState, approvedPendingVersions: ["20261103000000", "20261103000000"] });
  fs.writeFileSync(historyPath, "Local | Remote | Time (UTC)\n20261103000000 | | 2026-11-03\n");
  assert.equal(run("apply", historyPath).status, 1, "duplicate approved allowlist entries must block apply");

  const outsidePath = path.join(os.tmpdir(), "outside-migration-history.txt");
  fs.writeFileSync(outsidePath, "Local | Remote | Time (UTC)\n");
  const traversal = run("apply", path.relative(tempRoot, outsidePath));
  assert.notEqual(traversal.status, 0, "history path outside repository must be rejected");
  fs.rmSync(outsidePath, { force: true });

  console.log("[production-migration-baseline-gate] runtime fail-closed tests passed");
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
