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

export function classifyDeliveryFailure(error: unknown): DeliveryFailureClass {
  const code = typeof error === 'object' && error !== null && 'code' in error ? String((error as { code?: unknown }).code) : '';
  if (['AUTH', 'SCHEMA', 'UNSUPPORTED_STANDARD', 'INVALID_MESSAGE'].includes(code)) return 'permanent';
  if (['TIMEOUT', 'RATE_LIMIT', 'NETWORK', 'UNAVAILABLE'].includes(code)) return 'retryable';
  return 'quarantine';
}

export function evaluateIncomingEnvelope(value: unknown, store: IntegrationRuntimeStore): { decision: DeliveryDecision; envelope?: InteroperabilityEnvelope; reason?: string } {
  if (!validateEnvelope(value)) return { decision: 'reject', reason: 'Envelope failed structural validation' };
  const envelope = value;
  const existing = store.find(envelope.messageId);
  if (existing) return { decision: 'duplicate', envelope };
  store.enqueue({
    messageId: envelope.messageId,
    correlationId: envelope.correlationId,
    state: 'queued',
    attemptCount: 0,
  });
  return { decision: 'accept', envelope };
}

export function nextRetry(record: IntegrationDeliveryRecord, policy: IntegrationRuntimePolicy = DEFAULT_POLICY): IntegrationDeliveryRecord {
  if (policy.maxAttempts < 1 || policy.retryBaseDelayMs < 0) throw new Error('Invalid integration retry policy');
  if (record.attemptCount >= policy.maxAttempts) {
    return { ...record, state: 'quarantined', lastError: record.lastError ?? 'Maximum delivery attempts exceeded' };
  }
  const delay = policy.retryBaseDelayMs * 2 ** Math.max(0, record.attemptCount - 1);
  return { ...record, state: 'failed', nextAttemptAt: new Date(Date.now() + delay).toISOString() };
}

export function canReplay(record: IntegrationDeliveryRecord, context: IntegrationReplayContext): boolean {
  if (!context.authorised || !context.confirmed) return false;
  return ['failed', 'quarantined', 'replay_pending'].includes(record.state);
}
