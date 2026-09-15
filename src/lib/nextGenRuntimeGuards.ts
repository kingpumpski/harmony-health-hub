import { AIClinicalOutput } from './nextGenContracts';
import { assertClinicalActionSafe } from './nextGenClinicalSafety';
import { authorizeAIClinicalUse, AIModelGovernanceRecord, governClinicalOutput } from './nextGenAIGovernance';
import { evaluateCommunicationRequest, CommunicationPreferences, CommunicationRequest } from './nextGenCommunicationPolicy';
import { DeploymentProfile, isModuleAllowed, resolveDeploymentProfile, DeploymentProfileSource } from './nextGenDeploymentProfile';

export interface RuntimeGuardContext {
  authorised: boolean;
  confirmed: boolean;
  audited: boolean;
  online: boolean;
}

export function guardClinicalAction(action: string, context: RuntimeGuardContext): void {
  assertClinicalActionSafe(action, context);
}

export function guardAIOutput<T>(record: AIModelGovernanceRecord, output: AIClinicalOutput<T>): AIClinicalOutput<T> {
  const authorization = authorizeAIClinicalUse(record, output.intendedUse);
  if (!authorization.allowed) throw new Error(authorization.reason ?? 'AI use rejected');
  return governClinicalOutput(record, output);
}

export function guardCommunication(preferences: CommunicationPreferences, request: CommunicationRequest) {
  return evaluateCommunicationRequest(preferences, request);
}

export function guardDeploymentModule(source: DeploymentProfileSource, profileKey: string, moduleId: string, at = new Date()): DeploymentProfile {
  const profile = resolveDeploymentProfile(source, profileKey, at);
  if (!isModuleAllowed(profile, moduleId)) throw new Error(`Module ${moduleId} is not enabled for deployment profile ${profileKey}`);
  return profile;
}
