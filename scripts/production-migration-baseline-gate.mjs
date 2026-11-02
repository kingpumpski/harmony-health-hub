import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const statePath = path.join(root, "supabase", "production-migration-baseline.json");
const mode = process.argv.find((arg) => arg.startsWith("--mode="))?.split("=")[1]
  ?? process.argv[process.argv.indexOf("--mode") + 1]
  ?? "validate";

if (!["validate", "apply", "verify"].includes(mode)) {
  throw new Error(`Unsupported mode: ${mode}`);
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
  console.warn("Static migration checks may run, but this result is not a production migration validation.");
  process.exit(0);
}

if (mode === "verify") {
  console.log("[production-migration-baseline] Read-only verification mode; no migration apply is authorized by this gate.");
} else {
  console.log("[production-migration-baseline] Production migration baseline gate passed.");
}
