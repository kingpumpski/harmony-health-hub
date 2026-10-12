import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const source = readFileSync(new URL("../src/pages/patients/PatientHub.tsx", import.meta.url), "utf8");
const start = source.indexOf("list_insurance_companies");
assert.notEqual(start, -1, "Patient profile must load the canonical insurance directory");
const effect = source.slice(source.lastIndexOf("useEffect(", start), source.indexOf("const save =", start));
assert.match(effect, /try \{[\s\S]*?list_insurance_companies[\s\S]*?catch \(error: any\)/, "insurance directory RPC rejection must be handled");
assert.match(effect, /finally \{\s*if \(active\) setInsurersLoading\(false\);\s*\}/, "insurance loading indicator must reset after success, RPC error, or rejection");
assert.match(effect, /return \(\) => \{ active = false; \}/, "unmounted profile must ignore late insurance-directory results");
console.log("Patient insurance-directory resilience contract passed.");
