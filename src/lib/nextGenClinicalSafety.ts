export interface ClinicalSafetyCheck {
  id: string;
  description: string;
  blocking: boolean;
  passed: boolean;
}

export interface ClinicalActionGuard {
  action: string;
  requiresHumanConfirmation: boolean;
  requiresAuthorisedRole: boolean;
  requiresAudit: boolean;
  blockedWhenOffline: boolean;
}

const guards: ClinicalActionGuard[] = [
  { action: 'medication-administration', requiresHumanConfirmation: true, requiresAuthorisedRole: true, requiresAudit: true, blockedWhenOffline: false },
  { action: 'blood-product-administration', requiresHumanConfirmation: true, requiresAuthorisedRole: true, requiresAudit: true, blockedWhenOffline: true },
  { action: 'diagnostic-result-finalisation', requiresHumanConfirmation: true, requiresAuthorisedRole: true, requiresAudit: true, blockedWhenOffline: true },
  { action: 'ai-clinical-recommendation', requiresHumanConfirmation: true, requiresAuthorisedRole: true, requiresAudit: true, blockedWhenOffline: true },
  { action: 'appointment-claim', requiresHumanConfirmation: false, requiresAuthorisedRole: true, requiresAudit: true, blockedWhenOffline: false },
  { action: 'claim-adjudication', requiresHumanConfirmation: true, requiresAuthorisedRole: true, requiresAudit: true, blockedWhenOffline: false },
];

export function getClinicalActionGuard(action: string): ClinicalActionGuard | undefined {
  return guards.find((guard) => guard.action === action);
}

export function assertClinicalActionSafe(action: string, context: { authorised: boolean; confirmed: boolean; online: boolean }): void {
  const guard = getClinicalActionGuard(action);
  if (!guard) throw new Error(`No safety contract registered for clinical action: ${action}`);
  if (guard.requiresAuthorisedRole && !context.authorised) throw new Error(`Authorisation required for: ${action}`);
  if (guard.requiresHumanConfirmation && !context.confirmed) throw new Error(`Human confirmation required for: ${action}`);
  if (guard.blockedWhenOffline && !context.online) throw new Error(`Action unavailable while offline: ${action}`);
}
