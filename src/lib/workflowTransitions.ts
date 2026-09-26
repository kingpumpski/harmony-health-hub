export type WorkflowTransitionKind = 'emergency' | 'theatre' | 'transfusion' | 'insurance' | 'medication' | 'fertility';

const transitions: Record<WorkflowTransitionKind, Record<string, readonly string[]>> = {
  emergency: {
    waiting: ['triage', 'left_without_being_seen', 'cancelled'],
    triage: ['treatment', 'observation', 'admitted', 'referred', 'left_without_being_seen', 'cancelled'],
    treatment: ['observation', 'admitted', 'discharged', 'referred', 'cancelled'],
    observation: ['treatment', 'admitted', 'discharged', 'referred', 'cancelled'],
    admitted: ['discharged', 'referred'],
    discharged: [],
    referred: [],
    left_without_being_seen: [],
    cancelled: [],
  },
  theatre: {
    requested: ['approved', 'cancelled'],
    approved: ['scheduled', 'cancelled', 'postponed'],
    scheduled: ['in_progress', 'cancelled', 'postponed'],
    in_progress: ['completed'],
    postponed: ['scheduled', 'cancelled'],
    completed: [],
    cancelled: [],
  },
  transfusion: {
    issued: ['running', 'cancelled'],
    running: ['completed', 'stopped', 'cancelled'],
    completed: [],
    stopped: [],
    cancelled: [],
  },
  insurance: {
    draft: ['submitted'],
    submitted: ['acknowledged'],
    acknowledged: ['under_review'],
    under_review: ['approved', 'partially_approved', 'rejected', 'resubmission_required'],
    approved: ['paid'],
    partially_approved: ['paid'],
    rejected: ['resubmission_required'],
    resubmission_required: ['submitted'],
    paid: [],
    voided: [],
  },
  fertility: {
    active: ['completed', 'successful', 'unsuccessful', 'cancelled'],
    completed: [],
    successful: [],
    unsuccessful: [],
    cancelled: [],
  },
  medication: {
    scheduled: ['administered', 'held', 'refused', 'omitted', 'not_given', 'cancelled'],
    administered: [],
    held: [],
    refused: [],
    omitted: [],
    not_given: [],
    cancelled: [],
  },
};

export function normalizeWorkflowStatus(status: unknown): string {
  return String(status ?? '').trim().toLowerCase();
}

export function getAllowedWorkflowTransitions(
  kind: WorkflowTransitionKind,
  currentStatus: unknown,
): string[] {
  const normalized = normalizeWorkflowStatus(currentStatus);
  return [...(transitions[kind][normalized] ?? [])];
}

export function canTransitionWorkflow(
  kind: WorkflowTransitionKind,
  currentStatus: unknown,
  nextStatus: unknown,
): boolean {
  return getAllowedWorkflowTransitions(kind, currentStatus).includes(normalizeWorkflowStatus(nextStatus));
}
