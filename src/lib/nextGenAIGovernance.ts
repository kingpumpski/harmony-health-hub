import { AIClinicalOutput, requiresHumanReview } from './nextGenContracts';

export type AIModelLifecycle = 'proposed' | 'validated' | 'approved' | 'active' | 'restricted' | 'suspended' | 'retired';

const modelLifecycles: readonly AIModelLifecycle[] = ['proposed', 'validated', 'approved', 'active', 'restricted', 'suspended', 'retired'];

export interface AIModelGovernanceRecord {
  modelKey: string;
  version: string;
  lifecycle: AIModelLifecycle;
  intendedUses: string[];
  prohibitedUses: string[];
  evaluationPassed: boolean;
  evidenceReferences: string[];
}

export interface AIGovernanceDecision { allowed: boolean; reviewRequired: boolean; reason?: string; }

export function authorizeAIClinicalUse(record: AIModelGovernanceRecord, intendedUse: string): AIGovernanceDecision {
  if (!record || typeof record !== 'object') return { allowed: false, reviewRequired: true, reason: 'AI governance record is required' };
  if (!record.modelKey?.trim() || !record.version?.trim()) return { allowed:false, reviewRequired:true, reason:'Model identity is incomplete' };
  if (!modelLifecycles.includes(record.lifecycle)) return { allowed:false, reviewRequired:true, reason:'Model lifecycle is invalid' };
  if (record.lifecycle !== 'active') return { allowed:false, reviewRequired:true, reason:'Model is not active in the governed registry' };
  if (record.evaluationPassed !== true || !Array.isArray(record.evidenceReferences) || record.evidenceReferences.length === 0 || record.evidenceReferences.some((item) => typeof item !== 'string' || !item.trim())) return { allowed:false, reviewRequired:true, reason:'Required model evaluation evidence is not passed' };
  if (!intendedUse?.trim()) return { allowed:false, reviewRequired:true, reason:'AI intended use is required' };
  if (!Array.isArray(record.intendedUses) || record.intendedUses.some((item) => typeof item !== 'string' || !item.trim()) || !record.intendedUses.includes(intendedUse)) return { allowed:false, reviewRequired:true, reason:'Intended use is not registered' };
  if (!Array.isArray(record.prohibitedUses) || record.prohibitedUses.some((item) => typeof item !== 'string' || !item.trim())) return { allowed:false, reviewRequired:true, reason:'Prohibited-use registry is invalid' };
  if (record.prohibitedUses.includes(intendedUse)) return { allowed:false, reviewRequired:true, reason:'Intended use is explicitly prohibited' };
  return { allowed:true, reviewRequired:false };
}

export function governClinicalOutput<T>(record: AIModelGovernanceRecord, output: AIClinicalOutput<T>): AIClinicalOutput<T> {
  const decision = authorizeAIClinicalUse(record, output?.intendedUse);
  if (!decision.allowed) throw new Error(decision.reason ?? 'AI clinical use rejected by governance policy');
  if (output.modelKey !== record.modelKey || output.modelVersion !== record.version) throw new Error('AI output model identity does not match the governed registry record');
  if (!output.requestId?.trim()) throw new Error('AI output request ID is required');
  if (!Array.isArray(output.evidence) || output.evidence.length === 0 || output.evidence.some((item) => !item || typeof item.source !== 'string' || !item.source.trim())) throw new Error('AI clinical output requires valid evidence references');
  if (output.confidence !== undefined && (!Number.isFinite(output.confidence) || output.confidence < 0 || output.confidence > 1)) throw new Error('AI confidence must be between 0 and 1');
  if (typeof output.generatedAt !== 'string' || Number.isNaN(Date.parse(output.generatedAt))) throw new Error('AI output generatedAt is invalid');
  if (output.provenance?.auditRequired && !output.provenance.correlationId?.trim()) throw new Error('Audited AI output requires a correlation ID');
  const reviewRequired = requiresHumanReview(output.confidence) || output.review === 'required';
  return { ...output, review: reviewRequired ? 'required' : output.review };
}
