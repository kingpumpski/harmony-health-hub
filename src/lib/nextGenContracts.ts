export type IntegrationStandard = 'FHIR_R4' | 'FHIR_R5' | 'HL7_V2' | 'DICOM' | 'ASTM' | 'REST_JSON' | 'SOAP_XML';
export type IntegrationDirection = 'inbound' | 'outbound' | 'bidirectional';
export type IntegrationDeliveryState = 'received' | 'validated' | 'processed' | 'quarantined' | 'replayed' | 'failed';
export type AIReviewState = 'not-required' | 'required' | 'approved' | 'rejected';

const INTEGRATION_STANDARDS = new Set<IntegrationStandard>(['FHIR_R4', 'FHIR_R5', 'HL7_V2', 'DICOM', 'ASTM', 'REST_JSON', 'SOAP_XML']);
const INTEGRATION_DIRECTIONS = new Set<IntegrationDirection>(['inbound', 'outbound', 'bidirectional']);
const CLASSIFICATIONS = new Set<InteroperabilityEnvelope['classification']>(['clinical', 'operational', 'financial', 'administrative']);

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
  provenance?: {
    sourceSystem?: string;
    sourceRecordIds?: string[];
    correlationId?: string;
    auditRequired?: boolean;
  };
}

export function createCorrelationId(prefix = 'harmony'): string {
  const random = typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : Math.random().toString(36).slice(2);
  return `${prefix}-${random}`;
}

export function validateEnvelope(value: unknown): value is InteroperabilityEnvelope {
  if (!value || typeof value !== 'object') return false;
  const candidate = value as Partial<InteroperabilityEnvelope>;
  if (typeof candidate.messageId !== 'string' || candidate.messageId.trim() === '') return false;
  if (typeof candidate.correlationId !== 'string' || candidate.correlationId.trim() === '') return false;
  if (typeof candidate.sourceSystem !== 'string' || candidate.sourceSystem.trim() === '') return false;
  if (!INTEGRATION_STANDARDS.has(candidate.standard as IntegrationStandard)) return false;
  if (!INTEGRATION_DIRECTIONS.has(candidate.direction as IntegrationDirection)) return false;
  if (typeof candidate.eventType !== 'string' || candidate.eventType.trim() === '') return false;
  if (typeof candidate.schemaVersion !== 'string' || candidate.schemaVersion.trim() === '') return false;
  if (typeof candidate.occurredAt !== 'string' || Number.isNaN(Date.parse(candidate.occurredAt))) return false;
  if (!CLASSIFICATIONS.has(candidate.classification as InteroperabilityEnvelope['classification'])) return false;
  if ('destinationSystem' in candidate && candidate.destinationSystem !== undefined && typeof candidate.destinationSystem !== 'string') return false;
  if ('patientReference' in candidate && candidate.patientReference !== undefined && typeof candidate.patientReference !== 'string') return false;
  if (!('payload' in candidate) || candidate.payload === undefined) return false;
  return true;
}

export function requiresHumanReview(confidence?: number): boolean {
  return confidence === undefined || confidence < 0.85;
}
