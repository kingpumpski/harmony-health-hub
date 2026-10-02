import fs from "node:fs";
import assert from "node:assert/strict";

const healthApi=fs.readFileSync("src/lib/healthApi.ts","utf8");
for (const forbidden of [
  "createConsultationEncounter=async",
  "completeConsultation=async",
  "recordTriageVitals=async",
  "getCriticalPatients=async()=>[]",
  "getWaitingList=async()=>[]",
  "orderLabTest=async",
  "collectLabSample=async",
  "uploadLabResult=async",
  "validateLabResult=async",
  "getLabResults=async",
  "analyzeWithAI=async"
]) {
  assert.ok(!healthApi.includes(forbidden),`legacy mock API stub remains: ${forbidden}`);
}
console.log("[legacy-health-api-contract] no legacy mock clinical API stubs remain");
