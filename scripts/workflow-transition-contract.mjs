import {
  canTransitionWorkflow,
  getAllowedWorkflowTransitions,
  normalizeWorkflowStatus,
} from '../src/lib/workflowTransitions.ts';

const failures: string[] = [];
const assert = (name: string, condition: boolean) => {
  if (!condition) failures.push(name);
};

assert('status normalization trims and lowercases', normalizeWorkflowStatus('  UNDER_REVIEW ') === 'under_review');
assert('waiting emergency cannot skip triage to treatment', !canTransitionWorkflow('emergency', 'waiting', 'treatment'));
assert('waiting emergency can enter triage', canTransitionWorkflow('emergency', 'waiting', 'triage'));
assert('triage emergency can enter treatment', canTransitionWorkflow('emergency', 'triage', 'treatment'));
assert('closed emergency cannot transition', getAllowedWorkflowTransitions('emergency', 'discharged').length === 0);
assert('requested theatre can be approved', canTransitionWorkflow('theatre', 'requested', 'approved'));
assert('requested theatre cannot jump to in progress', !canTransitionWorkflow('theatre', 'requested', 'in_progress'));
assert('issued transfusion can start running', canTransitionWorkflow('transfusion', 'issued', 'running'));
assert('issued transfusion cannot complete directly', !canTransitionWorkflow('transfusion', 'issued', 'completed'));
assert('draft claim can be submitted', canTransitionWorkflow('insurance', 'draft', 'submitted'));
assert('draft claim cannot be paid directly', !canTransitionWorkflow('insurance', 'draft', 'paid'));
assert('under review claim can be adjudicated', canTransitionWorkflow('insurance', 'under_review', 'approved'));
assert('approved claim can be paid', canTransitionWorkflow('insurance', 'approved', 'paid'));
assert('scheduled medication can be administered', canTransitionWorkflow('medication', 'scheduled', 'administered'));
assert('administered medication cannot be administered again', !canTransitionWorkflow('medication', 'administered', 'administered'));

if (failures.length) {
  console.error('Workflow transition contract failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
} else {
  console.log('Workflow transition contract: all invariants passed');
}
