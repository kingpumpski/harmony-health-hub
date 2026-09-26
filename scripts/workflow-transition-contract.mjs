import fs from 'node:fs';
import path from 'node:path';

const source = fs.readFileSync(path.join(process.cwd(), 'src/lib/workflowTransitions.ts'), 'utf8');
const failures = [];
const assert = (name, condition) => {
  if (!condition) failures.push(name);
};

assert('workflow transition helper exists', source.includes('getAllowedWorkflowTransitions') && source.includes('canTransitionWorkflow'));
assert('status normalization is centralized', source.includes("trim().toLowerCase()"));
assert('emergency waiting cannot skip triage', source.includes("waiting: ['triage', 'left_without_being_seen', 'cancelled']"));
assert('emergency triage permits treatment', source.includes("triage: ['treatment', 'observation', 'admitted', 'referred', 'left_without_being_seen', 'cancelled']"));
assert('terminal emergency states have no outgoing transitions', source.includes('discharged: [],') && source.includes('referred: [],') && source.includes('cancelled: [],'));
assert('theatre lifecycle is sequential', source.includes("requested: ['approved', 'cancelled']") && source.includes("scheduled: ['in_progress', 'cancelled', 'postponed']"));
assert('transfusion lifecycle is sequential', source.includes("issued: ['running', 'cancelled']") && source.includes("running: ['completed', 'stopped', 'cancelled']"));
assert('insurance lifecycle is sequential', source.includes("draft: ['submitted']") && source.includes("under_review: ['approved', 'partially_approved', 'rejected', 'resubmission_required']") && source.includes("approved: ['paid']"));
assert('medication lifecycle only transitions from scheduled', source.includes("scheduled: ['administered', 'held', 'refused', 'omitted', 'not_given', 'cancelled']"));
assert('emergency board consumes centralized guard', fs.readFileSync(path.join(process.cwd(), 'src/pages/EmergencyBoard.tsx'), 'utf8').includes("canTransitionWorkflow('emergency'"));
assert('clinical operations consumes centralized guard', fs.readFileSync(path.join(process.cwd(), 'src/pages/ClinicalOperations.tsx'), 'utf8').includes('canTransitionWorkflow(tab'));
assert('insurance claims consumes centralized guard', fs.readFileSync(path.join(process.cwd(), 'src/pages/InsuranceClaims.tsx'), 'utf8').includes("canTransitionWorkflow('insurance'"));
assert('medication administration consumes centralized guard', fs.readFileSync(path.join(process.cwd(), 'src/pages/MedicationAdministration.tsx'), 'utf8').includes("canTransitionWorkflow('medication'"));
assert('clinical operations only renders permitted next statuses', fs.readFileSync(path.join(process.cwd(), 'src/pages/ClinicalOperations.tsx'), 'utf8').includes('getAllowedWorkflowTransitions('));
assert('emergency board only renders permitted next statuses', fs.readFileSync(path.join(process.cwd(), 'src/pages/EmergencyBoard.tsx'), 'utf8').includes("getAllowedWorkflowTransitions('emergency'"));
assert('insurance claims only renders permitted next statuses', fs.readFileSync(path.join(process.cwd(), 'src/pages/InsuranceClaims.tsx'), 'utf8').includes("getAllowedWorkflowTransitions('insurance'"));

if (failures.length) {
  console.error('Workflow transition contract failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
} else {
  console.log('Workflow transition contract: all invariants passed');
}
