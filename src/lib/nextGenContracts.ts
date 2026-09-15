export type IntegrationStandard = 'FHIR_R4' | 'FHIR_R5' | 'HL7_V2' | 'DICOM' | 'ASTM' | 'REST_JSON' | 'SOAP_XML';
export type IntegrationDirection = 'inbound' | 'outbound' | 'bidirectional';
export type IntegrationDeliveryState = 'received' | 'validated' | 'processed' | 'quarantined' | 'replayed' | 'failed';
export type AIReviewState = 'not-required' | 'required' | 'approved' | 'rejected';

export interface InteroperabilityEnvelope<TPayload = unknown> {
  messageId: string;
  correlationId: string;
  sourceSystem: string;
  destinationSystem?: string;
  standard: IntegrationStandard;
  direction: IntegrationDirection;
  eventType: string;
  schemaVersion: string;
  occurredAt: string;
  patientReference?: string;
  classification: 'clinical' | 'operational' | 'financial' | 'administrative';
  payload: TPayload;
}

export interface DeliveryAttempt {
  attempt: number;
  attemptedAt: string;
  state: IntegrationDeliveryState;
  errorCode?: string;
  errorMessage?: string;
}

export interface AIClinicalOutput<T = unknown> {
  requestId: string;
  modelKey: string;
  modelVersion: string;
  intendedUse: string;
  confidence?: number;
  uncertainty?: string;
  evidence: Array<{ source: string; locator?: string }>;
  review: AIReviewState;
  output: T;
  generatedAt: string;
}

export function createCorrelationId(prefix = 'harmony'): string {
  const random = typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : Math.random().toString(36).slice(2);
  return `${prefix}-${random}`;
}

export function validateEnvelope(value: unknown): value is InteroperabilityEnvelope {
  if (!value || typeof value !== 'object') return false;
  const candidate = value as Partial<InteroperabilityEnvelope>;
  return typeof candidate.messageId === 'string'
    && typeof candidate.correlationId === 'string'
    && typeof candidate.sourceSystem === 'string'
    && typeof candidate.standard === 'string'
    && typeof candidate.direction === 'string'
    && typeof candidate.eventType === 'string'
    && typeof candidate.schemaVersion === 'string'
    && typeof candidate.occurredAt === 'string'
    && typeof candidate.classification === 'string'
    && 'payload' in candidate;
}

export function requiresHumanReview(confidence?: number): boolean {
  return confidence === undefined || confidence < 0.85;
}
