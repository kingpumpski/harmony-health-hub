import { AIClinicalOutput, requiresHumanReview } from './nextGenContracts';

export type AIModelLifecycle = 'proposed' | 'validated' | 'approved' | 'active' | 'restricted' | 'suspended' | 'retired';

export interface AIModelGovernanceRecord {
  modelKey: string;
  version: string;
  lifecycle: AIModelLifecycle;
  intendedUses: string[];
  prohibitedUses: string[];
  evaluationPassed: boolean;
  evidenceReferences: string[];
}

export interface AIGovernanceDecision {
  allowed: boolean;
  reviewRequired: boolean;
  reason?: string;
}

export function authorizeAIClinicalUse(record: AIModelGovernanceRecord, intendedUse: string): AIGovernanceDecision {
  if (record.lifecycle !== 'active') return { allowed: false, reviewRequired: true, reason: 'Model is not active in the governed registry' };
  if (!record.evaluationPassed) return { allowed: false, reviewRequired: true, reason: 'Required model evaluation evidence is not passed' };
  if (!record.intendedUses.includes(intendedUse)) return { allowed: false, reviewRequired: true, reason: 'Intended use is not registered' };
  if (record.prohibitedUses.includes(intendedUse)) return { allowed: false, reviewRequired: true, reason: 'Intended use is explicitly prohibited' };
  return { allowed: true, reviewRequired: false };
}

export function governClinicalOutput<T>(record: AIModelGovernanceRecord, output: AIClinicalOutput<T>): AIClinicalOutput<T> {
  const decision = authorizeAIClinicalUse(record, output.intendedUse);
  if (!decision.allowed) throw new Error(decision.reason ?? 'AI clinical use rejected by governance policy');
  const reviewRequired = requiresHumanReview(output.confidence) || output.review === 'required';
  return { ...output, review: reviewRequired ? 'required' : output.review };
}
