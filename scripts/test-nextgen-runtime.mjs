import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const root = process.cwd();
const temp = mkdtempSync(join(tmpdir(), 'harmony-nextgen-'));

const expectThrow = (fn, message) => {
  try { fn(); } catch { return; }
  throw new Error(message);
};

try {
  execFileSync(process.platform === 'win32' ? 'npx.cmd' : 'npx', [
    'tsc', '--target', 'ES2022', '--module', 'commonjs', '--moduleResolution', 'node',
    '--skipLibCheck', '--esModuleInterop', '--outDir', temp,
    join(root, 'src/lib/nextGenContracts.ts'),
    join(root, 'src/lib/nextGenIntegrationRuntime.ts'),
    join(root, 'src/lib/nextGenAIGovernance.ts'),
    join(root, 'src/lib/nextGenCommunicationPolicy.ts'),
    join(root, 'src/lib/nextGenDeploymentProfile.ts'),
    join(root, 'src/lib/nextGenClinicalSafety.ts'),
    join(root, 'src/lib/nextGenRuntimeGuards.ts'),
  ], { cwd: root, stdio: 'inherit' });

  const require = createRequire(import.meta.url);
  const contracts = require(join(temp, 'nextGenContracts.js'));
  const integration = require(join(temp, 'nextGenIntegrationRuntime.js'));
  const ai = require(join(temp, 'nextGenAIGovernance.js'));
  const communication = require(join(temp, 'nextGenCommunicationPolicy.js'));
  const deployment = require(join(temp, 'nextGenDeploymentProfile.js'));
  const clinical = require(join(temp, 'nextGenClinicalSafety.js'));
  const guards = require(join(temp, 'nextGenRuntimeGuards.js'));

  const baseEnvelope = {
    messageId: 'msg-1', correlationId: 'corr-1', sourceSystem: 'test-source', destinationSystem: 'harmony',
    standard: 'FHIR_R4', direction: 'inbound', eventType: 'Patient.updated', schemaVersion: '1.0',
    occurredAt: new Date().toISOString(), classification: 'clinical', payload: { id: 'p1' },
  };

  for (const standard of ['FHIR_R4', 'FHIR_R5', 'HL7_V2', 'DICOM', 'ASTM', 'REST_JSON', 'SOAP_XML']) {
    if (!contracts.validateEnvelope({ ...baseEnvelope, messageId: `msg-${standard}`, standard })) throw new Error(`Supported interoperability standard rejected: ${standard}`);
  }
  for (const invalid of [
    { standard: 'NOT_A_STANDARD' }, { direction: 'sideways' }, { classification: 'restricted' },
    { occurredAt: 'not-a-date' }, { messageId: ' ' }, { correlationId: '' }, { sourceSystem: ' ' },
    { eventType: '' }, { schemaVersion: '' }, { payload: undefined }, { destinationSystem: 42 }, { patientReference: 42 },
  ]) if (contracts.validateEnvelope({ ...baseEnvelope, ...invalid })) throw new Error(`Invalid interoperability envelope accepted: ${JSON.stringify(invalid)}`);

  const store = new Map();
  const runtimeStore = { find: (id) => store.get(id), enqueue: (record) => store.set(record.messageId, record) };
  if (integration.evaluateIncomingEnvelope(baseEnvelope, runtimeStore).decision !== 'accept') throw new Error('First envelope not accepted');
  if (integration.evaluateIncomingEnvelope(baseEnvelope, runtimeStore).decision !== 'duplicate') throw new Error('Exact duplicate not rejected');
  const collision = integration.evaluateIncomingEnvelope({ ...baseEnvelope, payload: { id: 'different' } }, runtimeStore);
  if (collision.decision !== 'quarantine') throw new Error('Message ID collision with changed content was not quarantined');
  if (integration.evaluateIncomingEnvelope({ ...baseEnvelope, messageId: 'bad', standard: 'NOPE' }, runtimeStore).decision !== 'reject') throw new Error('Invalid envelope was accepted');

  for (const code of ['TIMEOUT', 'RATE_LIMIT', 'NETWORK', 'UNAVAILABLE']) if (integration.classifyDeliveryFailure({ code }) !== 'retryable') throw new Error(`Retryable failure misclassified: ${code}`);
  for (const code of ['AUTH', 'SCHEMA', 'UNSUPPORTED_STANDARD', 'INVALID_MESSAGE']) if (integration.classifyDeliveryFailure({ code }) !== 'permanent') throw new Error(`Permanent failure misclassified: ${code}`);
  if (integration.classifyDeliveryFailure({ code: 'UNKNOWN' }) !== 'quarantine') throw new Error('Unknown failure was not quarantined');

  const retry = integration.nextRetry({ messageId: 'm', correlationId: 'c', state: 'failed', attemptCount: 1 });
  if (retry.state !== 'failed' || !retry.nextAttemptAt) throw new Error('Retry scheduling failed');
  const secondRetry = integration.nextRetry({ ...retry, attemptCount: 2 });
  if (!secondRetry.nextAttemptAt || secondRetry.nextAttemptAt === retry.nextAttemptAt) throw new Error('Exponential retry scheduling failed');
  if (integration.nextRetry({ messageId: 'm', correlationId: 'c', state: 'failed', attemptCount: 5 }).state !== 'quarantined') throw new Error('Maximum-attempt quarantine failed');
  if (integration.nextRetry({ messageId: 'm', correlationId: 'c', state: 'delivered', attemptCount: 99 }).state !== 'delivered') throw new Error('Delivered record was incorrectly rescheduled');
  if (integration.nextRetry({ messageId: 'm', correlationId: 'c', state: 'replayed', attemptCount: 99 }).state !== 'replayed') throw new Error('Replayed record was incorrectly rescheduled');
  if (integration.nextRetry({ messageId: 'm', correlationId: 'c', state: 'failed', attemptCount: -1 }).state) throw new Error('Invalid attempt count accepted');
  if (integration.canReplay({ messageId: 'm', correlationId: 'c', state: 'quarantined', attemptCount: 5 }, { authorised: false, confirmed: true })) throw new Error('Unauthorized replay permitted');
  if (integration.canReplay({ messageId: 'm', correlationId: 'c', state: 'quarantined', attemptCount: 5 }, { authorised: true, confirmed: false })) throw new Error('Unconfirmed replay permitted');
  const replayable = { messageId: 'm', correlationId: 'c', state: 'quarantined', attemptCount: 5 };
  const pending = integration.prepareReplay(replayable, { authorised: true, confirmed: true });
  if (pending.state !== 'replay_pending' || !pending.nextAttemptAt) throw new Error('Replay transition to pending failed');
  const replayed = integration.markReplayed(pending, { authorised: true, confirmed: true });
  if (replayed.state !== 'replayed' || replayed.attemptCount !== 6) throw new Error('Replay completion transition failed');
  expectThrow(() => integration.markReplayed(replayable, { authorised: true, confirmed: true }), 'Replay bypassed pending state');
  expectThrow(() => integration.nextRetry({ ...retry }, { maxAttempts: 0, retryBaseDelayMs: 1000 }), 'Invalid retry policy accepted');
  expectThrow(() => integration.nextRetry({ ...retry }, { maxAttempts: 5.5, retryBaseDelayMs: 1000 }), 'Non-integer retry policy accepted');

  const model = { modelKey: 'test-model', version: '1', lifecycle: 'active', intendedUses: ['summarization'], prohibitedUses: ['diagnosis'], evaluationPassed: true, evidenceReferences: ['eval-1'] };
  const output = { requestId: 'r1', modelKey: 'test-model', modelVersion: '1', intendedUse: 'summarization', confidence: 0.84, evidence: [{ source: 'record' }], review: 'not-required', output: 'summary', generatedAt: new Date().toISOString() };
  if (ai.authorizeAIClinicalUse({ ...model, lifecycle: 'suspended' }, 'summarization').allowed) throw new Error('Suspended AI model authorized');
  if (ai.authorizeAIClinicalUse({ ...model, evaluationPassed: false }, 'summarization').allowed) throw new Error('Unevaluated AI model authorized');
  if (ai.authorizeAIClinicalUse({ ...model, evidenceReferences: [] }, 'summarization').allowed) throw new Error('AI model without evidence authorized');
  if (ai.authorizeAIClinicalUse(model, 'diagnosis').allowed) throw new Error('Prohibited AI use authorized');
  if (ai.authorizeAIClinicalUse(model, 'unregistered-use').allowed) throw new Error('Unregistered AI use authorized');
  if (ai.governClinicalOutput(model, output).review !== 'required') throw new Error('Low-confidence AI output did not escalate');
  if (ai.governClinicalOutput(model, { ...output, confidence: 0.85 }).review !== 'not-required') throw new Error('Threshold confidence incorrectly escalated');
  expectThrow(() => ai.governClinicalOutput(model, { ...output, intendedUse: 'diagnosis' }), 'Prohibited AI output was governed as safe');
  expectThrow(() => ai.governClinicalOutput({ ...model, lifecycle: 'restricted' }, output), 'Restricted AI model produced governed output');
  expectThrow(() => ai.governClinicalOutput(model, { ...output, modelVersion: '2' }), 'Unregistered model version produced governed output');
  expectThrow(() => ai.governClinicalOutput(model, { ...output, evidence: [] }), 'AI output without evidence was governed as safe');
  expectThrow(() => ai.governClinicalOutput(model, { ...output, confidence: 1.1 }), 'Out-of-range AI confidence accepted');
  expectThrow(() => ai.governClinicalOutput(model, { ...output, provenance: { auditRequired: true } }), 'Audited AI output without correlation ID accepted');

  const prefs = { preferredLanguage: 'en', preferredChannels: ['sms'], appointmentReminders: true, medicationReminders: true, resultNotifications: true, marketingMessages: false, quietHours: { start: '22:00', end: '07:00' } };
  if (communication.evaluateCommunicationRequest(prefs, { category: 'appointment', channel: 'sms', now: new Date('2026-01-01T23:00:00') }).allowed) throw new Error('Quiet-hours communication permitted');
  if (communication.evaluateCommunicationRequest(prefs, { category: 'marketing', channel: 'sms' }).allowed) throw new Error('Unconsented marketing communication permitted');
  if (communication.evaluateCommunicationRequest(prefs, { category: 'appointment', channel: 'email' }).allowed) throw new Error('Unconsented channel permitted');
  const operational = communication.evaluateCommunicationRequest(prefs, { category: 'operational', channel: 'sms', language: 'tw', containsSensitiveData: true });
  if (!operational.allowed || operational.language !== 'tw' || !operational.minimumNecessary) throw new Error('Operational minimum-necessary communication policy failed');
  if (communication.evaluateCommunicationRequest(prefs, { category: 'emergency', channel: 'email', emergency: true }).allowed) throw new Error('Emergency override bypassed channel authorization');
  const emergencyAllowed = communication.evaluateCommunicationRequest({ ...prefs, emergencyOverrideAllowed: true }, { category: 'emergency', channel: 'email', emergency: true, containsSensitiveData: true });
  if (!emergencyAllowed.allowed || !emergencyAllowed.minimumNecessary) throw new Error('Explicit emergency override was rejected');
  const malformedQuiet = communication.evaluateCommunicationRequest({ ...prefs, quietHours: { start: 'invalid', end: '07:00' } }, { category: 'appointment', channel: 'sms' });
  if (malformedQuiet.allowed || malformedQuiet.reason !== 'Invalid quiet-hours configuration') throw new Error('Malformed quiet-hours configuration did not fail closed');
  const malformedEnd = communication.evaluateCommunicationRequest({ ...prefs, quietHours: { start: '22:00', end: '25:00' } }, { category: 'appointment', channel: 'sms' });
  if (malformedEnd.allowed || malformedEnd.reason !== 'Invalid quiet-hours configuration') throw new Error('Malformed quiet-hours end did not fail closed');

  const activeProfile = {
    profileKey: 'gh', countryCode: 'GH', regionCode: 'GH-AA', locale: 'en-GH', timezone: 'Africa/Accra', currencyCode: 'GHS',
    dataResidencyRegion: 'GH', regulatoryProfile: 'ghana', clinicalProfile: 'default', communicationProfile: 'default',
    accessibilityProfile: 'wcag-2.2-aa', securityProfile: 'zero-trust', enabledModules: ['appointments', 'appointments'],
    effectiveFrom: '2026-01-01T00:00:00.000Z', effectiveTo: '2027-01-01T00:00:00.000Z',
  };
  const source = { findActive: () => activeProfile };
  const profile = deployment.resolveDeploymentProfile(source, 'gh', new Date('2026-06-01T00:00:00Z'));
  if (!deployment.isModuleAllowed(profile, 'appointments')) throw new Error('Enabled deployment module denied');
  if (profile.enabledModules.length !== 1) throw new Error('Deployment module de-duplication failed');
  if (deployment.isModuleAllowed(profile, 'pharmacy')) throw new Error('Disabled deployment module allowed');
  expectThrow(() => deployment.resolveDeploymentProfile(source, 'gh', new Date('2025-12-01T00:00:00Z')), 'Inactive deployment profile accepted');
  expectThrow(() => deployment.resolveDeploymentProfile(source, 'gh', new Date('2027-01-01T00:00:00Z')), 'Expired deployment profile accepted at boundary');
  expectThrow(() => deployment.resolveDeploymentProfile({ findActive: () => undefined }, 'gh', new Date()), 'Missing deployment profile accepted');

  for (const context of [
    { authorised: false, confirmed: true, audited: true, online: true },
    { authorised: true, confirmed: false, audited: true, online: true },
    { authorised: true, confirmed: true, audited: false, online: true },
    { authorised: true, confirmed: true, audited: true, online: false },
  ]) expectThrow(() => guards.guardClinicalAction('medication-administration', context), 'Unsafe clinical action permitted');
  expectThrow(() => guards.guardClinicalAction('unknown-clinical-action', { authorised: true, confirmed: true, audited: true, online: true }), 'Unknown clinical action permitted');
  clinical.assertClinicalActionSafe('medication-administration', { authorised: true, confirmed: true, audited: true, online: true });
  expectThrow(() => clinical.assertClinicalActionSafe('blood-product-administration', { authorised: true, confirmed: true, audited: true, online: false }), 'Offline critical clinical action permitted');
  expectThrow(() => guards.guardAIOutput({ ...model, evaluationPassed: false }, output), 'Unevaluated AI output permitted by runtime guard');
  expectThrow(() => guards.guardAIOutput({ ...model, lifecycle: 'active' }, { ...output, intendedUse: 'diagnosis' }), 'Prohibited AI output permitted by runtime guard');
  expectThrow(() => guards.guardDeploymentModule({ findActive: () => activeProfile }, 'gh', 'pharmacy', new Date('2026-06-01T00:00:00Z')), 'Disabled deployment module permitted');
  expectThrow(() => guards.guardCommunication(prefs, { category: 'marketing', channel: 'sms' }), 'Unconsented communication permitted by runtime guard');

  console.log('Next-gen runtime, interoperability, AI governance, communication, deployment, and clinical safety adversarial tests passed.');
} finally {
  rmSync(temp, { recursive: true, force: true });
}
