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

const artifact = state.verification?.mappingArtifact;
const artifactPath = typeof artifact === "string" && artifact.trim()
  ? path.resolve(root, artifact)
  : "";
const artifactRelative = artifactPath ? path.relative(root, artifactPath) : "";
const artifactInsideRepository = Boolean(artifactPath)
  && artifactRelative !== ""
  && !artifactRelative.startsWith("..")
  && !path.isAbsolute(artifactRelative);
const artifactExists = artifactInsideRepository && fs.existsSync(artifactPath)
  && fs.statSync(artifactPath).isFile()
  && fs.statSync(artifactPath).size > 0;
const baselineMappingsVerified = Array.isArray(state.knownBaseline)
  && state.knownBaseline.length > 0
  && state.knownBaseline.every((entry) =>
    entry
    && entry.mappingStatus === "verified"
    && typeof entry.mappedTo === "string" && entry.mappedTo.trim().length > 0
    && typeof entry.mappingEvidence === "string" && entry.mappingEvidence.trim().length > 0
  );
const reviewedCommitValid = typeof state.verification?.reviewedCommit === "string"
  && /^[0-9a-f]{40}$/i.test(state.verification.reviewedCommit);
const verifiedAtValid = typeof state.verification?.verifiedAt === "string"
  && Number.isFinite(Date.parse(state.verification.verifiedAt));
const approvedByValid = typeof state.verification?.approvedBy === "string"
  && state.verification.approvedBy.trim().length > 0;

const verified = state.status === "verified"
  && state.productionPushAllowed === true
  && verifiedAtValid
  && reviewedCommitValid
  && artifactExists
  && baselineMappingsVerified
  && approvedByValid;

if (mode === "verify") {
  console.log("[production-migration-baseline] Read-only verification mode; no migration apply is authorized by this gate.");
  if (!verified) {
    console.warn("[production-migration-baseline] NOTICE: production baseline remains unreconciled; this mode does not validate or authorize migration apply.");
  }
  process.exit(0);
}

if (!verified) {
  console.error("[production-migration-baseline] BLOCKED: production migration baseline is not fully verified.");
  console.error("Required: verified baseline mappings, a non-empty in-repository evidence artifact, valid reviewed commit/date, and named approval.");
  console.error("No production migration validation or apply may proceed until provenance is reviewed and approved.");
  process.exit(mode === "apply" ? 1 : 2);
}

if (!historyFile) {
  throw new Error("A linked migration history file is required for validate/apply baseline checks.");
}
const resolvedHistoryPath = path.resolve(root, historyFile);
const historyRelative = path.relative(root, resolvedHistoryPath);
if (historyRelative === "" || historyRelative.startsWith("..") || path.isAbsolute(historyRelative)) {
  throw new Error("Linked migration history file must be inside the repository.");
}
if (!fs.existsSync(resolvedHistoryPath) || !fs.statSync(resolvedHistoryPath).isFile()) {
  throw new Error("Linked migration history file not found: " + resolvedHistoryPath);
}

const localPending = [];
const seenLocal = new Set();
const seenRemote = new Set();
const lines = fs.readFileSync(resolvedHistoryPath, "utf8").split(/\r?\n/);
for (const line of lines) {
  if (!line.includes("|")) continue;
  const columns = line.split("|");
  if (columns.length < 2) continue;
  const local = columns[0].trim().replace(/[\x60"]/g, "");
  const remote = columns[1].trim().replace(/[\x60"]/g, "");
  const localDigits = /^\d+$/.test(local);
  const remoteDigits = /^\d+$/.test(remote);
  if (localDigits && !/^\d{14}$/.test(local)) {
    throw new Error("Malformed local migration version in linked history: " + line);
  }
  if (remoteDigits && !/^\d{14}$/.test(remote)) {
    throw new Error("Malformed remote migration version in linked history: " + line);
  }
  const localVersion = /^\d{14}$/.test(local) ? local : "";
  const remoteVersion = /^\d{14}$/.test(remote) ? remote : "";
  if (!localVersion && !remoteVersion) continue;
  if (localVersion && remoteVersion && localVersion !== remoteVersion) {
    throw new Error("Ambiguous local/remote migration row; refusing production apply: " + line);
  }
  if (localVersion) {
    if (seenLocal.has(localVersion)) throw new Error("Duplicate local migration version in linked history: " + localVersion);
    seenLocal.add(localVersion);
  }
  if (remoteVersion) {
    if (seenRemote.has(remoteVersion)) throw new Error("Duplicate remote migration version in linked history: " + remoteVersion);
    seenRemote.add(remoteVersion);
  }
  if (localVersion && !remoteVersion) localPending.push(localVersion);
}

const actual = [...localPending].sort();
if (!Array.isArray(state.approvedPendingVersions)) {
  throw new Error("approvedPendingVersions must be an explicit array in baseline state.");
}
const approvedRaw = state.approvedPendingVersions;
const approved = [...approvedRaw].sort();
if (new Set(approved).size !== approved.length) {
  throw new Error("approvedPendingVersions must not contain duplicate entries.");
}
const invalidApproved = approved.filter((version) => typeof version !== "string" || !/^\d{14}$/.test(version));
if (invalidApproved.length) throw new Error("Invalid approved migration versions: " + invalidApproved.join(", "));

if (JSON.stringify(actual) !== JSON.stringify(approved)) {
  console.error("[production-migration-baseline] BLOCKED: linked local-pending migration versions do not exactly match the reviewed allowlist.");
  console.error("Observed pending versions: " + (actual.join(", ") || "(none)"));
  console.error("Approved pending versions: " + (approved.join(", ") || "(none)"));
  process.exit(1);
}

console.log("[production-migration-baseline] History precheck passed; " + actual.length + " pending migration(s) exactly match the approved allowlist.");
if (mode === "validate") {
  console.log("This is a history precheck only; it does not execute a production SQL dry-run or apply.");
}
