export type AIReviewRequirement = 'none' | 'clinician' | 'specialist' | 'safety-board';
export type AIActionClass = 'summarization' | 'documentation' | 'decision-support' | 'risk-scoring' | 'clinical-order' | 'diagnosis';

export interface AIUseContext {
  modelState: 'proposed' | 'validated' | 'approved' | 'active' | 'restricted' | 'suspended' | 'retired';
  intendedUse: string;
  actionClass: AIActionClass;
  confidence?: number;
  patientFacing: boolean;
  hasHumanReviewer: boolean;
  sourceCount: number;
  uncertaintyDeclared: boolean;
}

export interface AIGovernanceDecision {
  allowed: boolean;
  review: AIReviewRequirement;
  reasons: string[];
}

const autonomousClinicalClasses = new Set<AIActionClass>(['clinical-order', 'diagnosis']);

export function evaluateAIUse(context: AIUseContext): AIGovernanceDecision {
  const reasons: string[] = [];
  if (!['approved', 'active'].includes(context.modelState)) reasons.push('model is not approved for clinical use');
  if (context.sourceCount < 1) reasons.push('no governed source evidence supplied');
  if (!context.uncertaintyDeclared) reasons.push('uncertainty must be declared for clinical assistance');
  if (autonomousClinicalClasses.has(context.actionClass)) reasons.push('autonomous clinical action is prohibited by the reference architecture');
  if (context.patientFacing && !context.hasHumanReviewer) reasons.push('patient-facing clinical output requires human review');

  let review: AIReviewRequirement = 'none';
  if (context.actionClass === 'diagnosis' || context.actionClass === 'clinical-order') review = 'specialist';
  else if (context.actionClass === 'decision-support' || context.actionClass === 'risk-scoring') review = 'clinician';
  else if (context.patientFacing) review = 'clinician';
  if (context.confidence !== undefined && context.confidence < 0.85) review = review === 'none' ? 'clinician' : review;

  return { allowed: reasons.length === 0, review, reasons };
}

export function requiresEscalation(confidence: number | undefined, threshold = 0.85): boolean {
  return confidence === undefined || confidence < threshold;
}
