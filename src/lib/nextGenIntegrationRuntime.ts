import { InteroperabilityEnvelope, validateEnvelope } from './nextGenContracts';

export type DeliveryDecision = 'accept' | 'duplicate' | 'reject' | 'quarantine';
export type DeliveryFailureClass = 'retryable' | 'permanent' | 'quarantine';

export interface IntegrationDeliveryRecord {
  messageId: string;
  correlationId: string;
  state: 'queued' | 'processing' | 'delivered' | 'failed' | 'quarantined' | 'replay_pending' | 'replayed';
  attemptCount: number;
  nextAttemptAt?: string;
  lastError?: string;
  payloadFingerprint?: string;
}

export interface IntegrationRuntimePolicy {
  maxAttempts: number;
  retryBaseDelayMs: number;
}

export interface IntegrationRuntimeStore {
  find(messageId: string): IntegrationDeliveryRecord | undefined;
  enqueue(record: IntegrationDeliveryRecord): void;
}

export interface IntegrationReplayContext {
  authorised: boolean;
  confirmed: boolean;
}

const DEFAULT_POLICY: IntegrationRuntimePolicy = { maxAttempts: 5, retryBaseDelayMs: 1000 };

function stablePayloadFingerprint(envelope: InteroperabilityEnvelope): string {
  const serialised = JSON.stringify({
    sourceSystem: envelope.sourceSystem,
    destinationSystem: envelope.destinationSystem,
    standard: envelope.standard,
    direction: envelope.direction,
    eventType: envelope.eventType,
    schemaVersion: envelope.schemaVersion,
    occurredAt: envelope.occurredAt,
    patientReference: envelope.patientReference,
    classification: envelope.classification,
    payload: envelope.payload,
  });
  let hash = 2166136261;
  for (let index = 0; index < serialised.length; index += 1) {
    hash ^= serialised.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

function validateRetryPolicy(policy: IntegrationRuntimePolicy): void {
  if (!Number.isInteger(policy.maxAttempts) || policy.maxAttempts < 1 || policy.retryBaseDelayMs < 0 || !Number.isFinite(policy.retryBaseDelayMs)) {
    throw new Error('Invalid integration retry policy');
  }
}

export function classifyDeliveryFailure(error: unknown): DeliveryFailureClass {
  const code = typeof error === 'object' && error !== null && 'code' in error ? String((error as { code?: unknown }).code) : '';
  if (['AUTH', 'SCHEMA', 'UNSUPPORTED_STANDARD', 'INVALID_MESSAGE'].includes(code)) return 'permanent';
  if (['TIMEOUT', 'RATE_LIMIT', 'NETWORK', 'UNAVAILABLE'].includes(code)) return 'retryable';
  return 'quarantine';
}

export function evaluateIncomingEnvelope(value: unknown, store: IntegrationRuntimeStore): { decision: DeliveryDecision; envelope?: InteroperabilityEnvelope; reason?: string } {
  if (!validateEnvelope(value)) return { decision: 'reject', reason: 'Envelope failed structural validation' };
  const envelope = value;
  const fingerprint = stablePayloadFingerprint(envelope);
  const existing = store.find(envelope.messageId);
  if (existing) {
    if (existing.payloadFingerprint && existing.payloadFingerprint !== fingerprint) {
      return { decision: 'quarantine', envelope, reason: 'Message ID collision with different envelope content' };
    }
    return { decision: 'duplicate', envelope, reason: 'Message already registered' };
  }
  store.enqueue({
    messageId: envelope.messageId,
    correlationId: envelope.correlationId,
    state: 'queued',
    attemptCount: 0,
    payloadFingerprint: fingerprint,
  });
  return { decision: 'accept', envelope };
}

export function nextRetry(record: IntegrationDeliveryRecord, policy: IntegrationRuntimePolicy = DEFAULT_POLICY): IntegrationDeliveryRecord {
  validateRetryPolicy(policy);
  if (!Number.isInteger(record.attemptCount) || record.attemptCount < 0) throw new Error('Invalid integration attempt count');
  if (record.state === 'delivered' || record.state === 'replayed') return record;
  if (record.state === 'quarantined') return record;
  if (record.state !== 'failed') throw new Error(`Retry requires failed state, received ${record.state}`);
  if (record.attemptCount >= policy.maxAttempts) {
    return { ...record, state: 'quarantined', nextAttemptAt: undefined, lastError: record.lastError ?? 'Maximum delivery attempts exceeded' };
  }
  const delay = policy.retryBaseDelayMs * 2 ** record.attemptCount;
  return { ...record, state: 'failed', nextAttemptAt: new Date(Date.now() + delay).toISOString() };
}

export function canReplay(record: IntegrationDeliveryRecord, context: IntegrationReplayContext): boolean {
  if (!context.authorised || !context.confirmed) return false;
  return ['failed', 'quarantined'].includes(record.state);
}

export function prepareReplay(record: IntegrationDeliveryRecord, context: IntegrationReplayContext): IntegrationDeliveryRecord {
  if (!canReplay(record, context)) throw new Error('Replay requires authorization, confirmation, and a replayable state');
  return { ...record, state: 'replay_pending', nextAttemptAt: new Date().toISOString() };
}

export function markReplayed(record: IntegrationDeliveryRecord, context: IntegrationReplayContext): IntegrationDeliveryRecord {
  if (!context.authorised || !context.confirmed) throw new Error('Replay completion requires authorization and confirmation');
  if (record.state !== 'replay_pending') throw new Error('Only replay-pending messages can be marked replayed');
  return { ...record, state: 'replayed', nextAttemptAt: undefined, attemptCount: record.attemptCount + 1 };
}
