export type IntegrationStandard = 'FHIR_R4' | 'FHIR_R5' | 'HL7_V2' | 'DICOM' | 'ASTM' | 'REST_JSON' | 'XML_SOAP';
export type IntegrationDirection = 'inbound' | 'outbound' | 'bidirectional';
export type DeliveryState = 'accepted' | 'processed' | 'retrying' | 'quarantined' | 'rejected';

export interface IntegrationEnvelope<T = unknown> {
  messageId: string;
  correlationId: string;
  source: string;
  destination: string;
  standard: IntegrationStandard;
  direction: IntegrationDirection;
  schemaVersion: string;
  occurredAt: string;
  idempotencyKey: string;
  classification: 'clinical' | 'operational' | 'financial' | 'restricted';
  payload: T;
}

export interface DeliveryAttempt {
  attempt: number;
  state: DeliveryState;
  occurredAt: string;
  errorCode?: string;
  errorMessage?: string;
}

const MAX_RETRIES = 5;

export function createIdempotencyKey(envelope: Pick<IntegrationEnvelope, 'source' | 'destination' | 'messageId'>): string {
  return `${envelope.source}:${envelope.destination}:${envelope.messageId}`;
}

export function nextDeliveryState(attempt: number, errorClass: 'transient' | 'permanent' | 'validation'): DeliveryState {
  if (errorClass === 'permanent' || errorClass === 'validation') return 'quarantined';
  return attempt >= MAX_RETRIES ? 'quarantined' : 'retrying';
}

export function isDuplicateMessage(existingKeys: ReadonlySet<string>, idempotencyKey: string): boolean {
  return existingKeys.has(idempotencyKey);
}

export function validateEnvelope(envelope: IntegrationEnvelope): string[] {
  const errors: string[] = [];
  if (!envelope.messageId.trim()) errors.push('messageId is required');
  if (!envelope.correlationId.trim()) errors.push('correlationId is required');
  if (!envelope.source.trim()) errors.push('source is required');
  if (!envelope.destination.trim()) errors.push('destination is required');
  if (!envelope.schemaVersion.trim()) errors.push('schemaVersion is required');
  if (!envelope.idempotencyKey.trim()) errors.push('idempotencyKey is required');
  if (Number.isNaN(Date.parse(envelope.occurredAt))) errors.push('occurredAt must be an ISO date');
  return errors;
}

export const deviceLifecycleStates = ['proposed', 'onboarding', 'validation', 'active', 'degraded', 'quarantined', 'maintenance', 'retired'] as const;
export type DeviceLifecycleState = typeof deviceLifecycleStates[number];

export function canTransitionDevice(current: DeviceLifecycleState, next: DeviceLifecycleState): boolean {
  const transitions: Record<DeviceLifecycleState, readonly DeviceLifecycleState[]> = {
    proposed: ['onboarding', 'retired'],
    onboarding: ['validation', 'quarantined', 'retired'],
    validation: ['active', 'quarantined', 'maintenance', 'retired'],
    active: ['degraded', 'quarantined', 'maintenance', 'retired'],
    degraded: ['active', 'quarantined', 'maintenance', 'retired'],
    quarantined: ['validation', 'maintenance', 'retired'],
    maintenance: ['validation', 'active', 'quarantined', 'retired'],
    retired: [],
  };
  return transitions[current].includes(next);
}
