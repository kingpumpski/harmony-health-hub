import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const statePath = path.join(root, "supabase", "production-migration-baseline.json");
const args = process.argv.slice(2);
const argValue = (name) => {
  const index = args.indexOf(name);
  if (index >= 0) return args[index + 1];
  const inline = args.find((arg) => arg.startsWith(name + "="));
  return inline?.slice(name.length + 1);
};
const mode = argValue("--mode") ?? "validate";
const historyFile = argValue("--history-file");

if (!["validate", "apply", "verify"].includes(mode)) {
  throw new Error("Unsupported mode: " + mode);
}
if (!fs.existsSync(statePath)) throw new Error("Production migration baseline state file is missing.");

const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
if (state.projectRef !== "ygqoptvezotdqhtimdkr") {
  throw new Error("Baseline projectRef does not match the configured production project.");
}

const verified = state.status === "verified"
  && state.productionPushAllowed === true
  && state.verification?.verifiedAt
  && state.verification?.reviewedCommit
  && state.verification?.mappingArtifact
  && state.verification?.approvedBy;

if (mode === "apply" && !verified) {
  console.error("[production-migration-baseline] BLOCKED: production migration baseline is not verified.");
  console.error("No production migration command may run until the provenance mapping is reviewed and approved.");
  process.exit(1);
}

if (mode === "validate" && !verified) {
  console.warn("[production-migration-baseline] BLOCKED: production dry-run skipped because historical migration provenance is unresolved.");
  console.warn("This is not a production migration validation. No SQL was applied or dry-run.");
  process.exit(0);
}

if (mode === "verify") {
  console.log("[production-migration-baseline] Read-only verification mode; no migration apply is authorized by this gate.");
  process.exit(0);
}

if (!historyFile) {
  throw new Error("A linked migration history file is required for validate/apply baseline checks.");
}
const resolvedHistoryPath = path.resolve(root, historyFile);
if (!fs.existsSync(resolvedHistoryPath)) {
  throw new Error("Linked migration history file not found: " + resolvedHistoryPath);
}

const localPending = [];
const lines = fs.readFileSync(resolvedHistoryPath, "utf8").split(/\r?\n/);
for (const line of lines) {
  if (!line.includes("|")) continue;
  const columns = line.split("|");
  if (columns.length < 2) continue;
  const local = columns[0].trim().replace(/[\x60"]/g, "");
  const remote = columns[1].trim().replace(/[\x60"]/g, "");
  const localVersion = /^\d{14}$/.test(local) ? local : "";
  const remoteVersion = /^\d{14}$/.test(remote) ? remote : "";
  if (!localVersion && !remoteVersion) continue;
  if (localVersion && remoteVersion && localVersion !== remoteVersion) {
    throw new Error("Ambiguous local/remote migration row; refusing production apply: " + line);
  }
  if (localVersion && !remoteVersion) localPending.push(localVersion);
}

const actual = [...new Set(localPending)].sort();
const approved = Array.isArray(state.approvedPendingVersions)
  ? [...new Set(state.approvedPendingVersions)].sort()
  : null;
if (!approved) throw new Error("approvedPendingVersions must be an explicit array in baseline state.");
const invalidApproved = approved.filter((version) => !/^\d{14}$/.test(version));
if (invalidApproved.length) throw new Error("Invalid approved migration versions: " + invalidApproved.join(", "));

if (JSON.stringify(actual) !== JSON.stringify(approved)) {
  console.error("[production-migration-baseline] BLOCKED: linked local-pending migration versions do not exactly match the reviewed allowlist.");
  console.error("Observed pending versions: " + (actual.join(", ") || "(none)"));
  console.error("Approved pending versions: " + (approved.join(", ") || "(none)"));
  process.exit(1);
}

console.log("[production-migration-baseline] History precheck passed; " + actual.length + " pending migration(s) exactly match the approved allowlist.");
if (mode === "validate") {
  console.log("No SQL dry-run was executed. Run local replay and SQL validation before requesting production apply.");
}
