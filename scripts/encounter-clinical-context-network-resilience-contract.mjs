import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const source = readFileSync(new URL("../src/pages/Encounters.tsx", import.meta.url), "utf8");

assert.match(source, /function BMIContextCard[\s\S]*?try \{[\s\S]*?get_patient_bmi_context[\s\S]*?catch \(loadError\)/,
  "BMI context requests must handle rejected promises");
assert.match(source, /function ClinicalSafetyContext[\s\S]*?get_encounter_clinical_context[\s\S]*?catch \(loadError\)[\s\S]*?finally \{[\s\S]*?if \(active\) setLoading\(false\)/,
  "clinical safety context must handle network rejection and clear loading state");
assert.match(source, /const loadAll = useCallback\(async \(\) => \{[\s\S]*?searchPatientDirectory\("", 1000\)[\s\S]*?catch \(loadError\)[\s\S]*?Encounter workspace unavailable[\s\S]*?finally \{\s*setLoading\(false\);/,
  "encounter worklist must handle thrown network failures and always clear loading");
assert.match(source, /if \(patientDirectory\.error\)[\s\S]*?\} else \{\s*const directoryPatients = \(patientDirectory\.data \?\? \[\]\)[\s\S]*?setPatients\(/,
  "a failed patient-directory refresh must not replace previously loaded patients with an empty list");
assert.match(source, /if \(encounterError\)[\s\S]*?\} else \{\s*setEncounters\(\(encs \?\? \[\]\) as Encounter\[\]\)/,
  "a failed encounter refresh must retain the last successful encounter list");

console.log("Encounter clinical-context network-resilience contract passed.");
