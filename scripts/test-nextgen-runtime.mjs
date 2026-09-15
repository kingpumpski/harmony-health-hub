import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const root = process.cwd();
const temp = mkdtempSync(join(tmpdir(), 'harmony-nextgen-'));

const expectThrow = (fn, message) => {
  try {
    fn();
  } catch {
    return;
  }
  throw new Error(message);
};

try {
  execFileSync(process.platform === 'win32' ? 'npx.cmd' : 'npx', [
    'tsc',
    '--target', 'ES2022',
    '--module', 'commonjs',
    '--moduleResolution', 'node',
    '--skipLibCheck',
    '--esModuleInterop',
    '--outDir', temp,
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
    messageId: 'msg-1', correlationId: 'corr-1', sourceSystem: 'test-source',
    destinationSystem: 'harmony', standard: 'FHIR_R4', direction: 'inbound',
    eventType: 'Patient.updated', schemaVersion: '1.0', occurredAt: new Date().toISOString(),
    classification: 'clinical', payload: { id: 'p1' },
  };

  for (const standard of ['FHIR_R4', 'FHIR_R5', 'HL7_V2', 'DICOM', 'ASTM', 'REST_JSON', 'SOAP_XML']) {
    if (!contracts.validateEnvelope({ ...baseEnvelope, messageId: `msg-${standard}`, standard })) {
      throw new Error(`Supported interoperability standard rejected: ${standard}`);
    }
  }
  if (contracts.validateEnvelope({ ...baseEnvelope, standard: 'NOT_A_STANDARD' })) throw new Error('Unsupported standard accepted');
  if (contracts.validateEnvelope({ ...baseEnvelope, direction: 'sideways' })) throw new Error('Unsupported direction accepted');
  if (contracts.validateEnvelope({ ...baseEnvelope, classification: 'restricted' })) throw new Error('Unsupported classification accepted');
  if (contracts.validateEnvelope({ ...baseEnvelope, occurredAt: 'not-a-date' })) throw new Error('Invalid timestamp accepted');
  if (contracts.validateEnvelope({ ...baseEnvelope, messageId: ' ' })) throw new Error('Blank message ID accepted');
  if (contracts.validateEnvelope({ ...baseEnvelope, payload: undefined })) throw new Error('Missing payload accepted');

  const store = new Map();
  const runtimeStore = { find: (id) => store.get(id), enqueue: (record) => store.set(record.messageId, record) };
  if (integration.evaluateIncomingEnvelope(baseEnvelope, runtimeStore).decision !== 'accept') throw new Error('First envelope not accepted');
  if (integration.evaluateIncomingEnvelope(baseEnvelope, runtimeStore).decision !== 'duplicate') throw new Error('Duplicate envelope not rejected');
  if (integration.evaluateIncomingEnvelope({ ...baseEnvelope, messageId: 'bad', standard: 'NOPE' }, runtimeStore).decision !== 'reject') throw new Error('Invalid envelope was accepted');

  for (const code of ['TIMEOUT', 'RATE_LIMIT', 'NETWORK', 'UNAVAILABLE']) {
    if (integration.classifyDeliveryFailure({ code }) !== 'retryable') throw new Error(`Retryable failure misclassified: ${code}`);
  }
  for (const code of ['AUTH', 'SCHEMA', 'UNSUPPORTED_STANDARD', 'INVALID_MESSAGE']) {
    if (integration.classifyDeliveryFailure({ code }) !== 'permanent') throw new Error(`Permanent failure misclassified: ${code}`);
  }
  if (integration.classifyDeliveryFailure({ code: 'UNKNOWN' }) !== 'quarantine') throw new Error('Unknown failure was not quarantined');

  const retry = integration.nextRetry({ messageId: 'm', correlationId: 'c', state: 'failed', attemptCount: 1 });
  if (retry.state !== 'failed' || !retry.nextAttemptAt) throw new Error('Retry scheduling failed');
  const secondRetry = integration.nextRetry({ ...retry, attemptCount: 2 });
  if (!secondRetry.nextAttemptAt || secondRetry.nextAttemptAt === retry.nextAttemptAt) throw new Error('Exponential retry scheduling failed');
  const quarantined = integration.nextRetry({ messageId: 'm', correlationId: 'c', state: 'failed', attemptCount: 5 });
  if (quarantined.state !== 'quarantined') throw new Error('Maximum-attempt quarantine failed');
  if (integration.canReplay(quarantined, { authorised: false, confirmed: true })) throw new Error('Unauthorized replay permitted');
  if (integration.canReplay(quarantined, { authorised: true, confirmed: false })) throw new Error('Unconfirmed replay permitted');
  if (!integration.canReplay(quarantined, { authorised: true, confirmed: true })) throw new Error('Authorized replay rejected');
  expectThrow(() => integration.nextRetry({ ...retry }, { maxAttempts: 0, retryBaseDelayMs: 1000 }), 'Invalid retry policy accepted');

  const model = { modelKey: 'test-model', version: '1', lifecycle: 'active', intendedUses: ['summarization'], prohibitedUses: ['diagnosis'], evaluationPassed: true, evidenceReferences: ['eval-1'] };
  const output = { requestId: 'r1', modelKey: 'test-model', modelVersion: '1', intendedUse: 'summarization', confidence: 0.84, evidence: [{ source: 'record' }], review: 'not-required', output: 'summary', generatedAt: new Date().toISOString() };
  if (!ai.authorizeAIClinicalUse({ ...model, lifecycle: 'suspended' }, 'summarization').allowed) throw new Error('Suspended AI model authorized');
  if (!ai.authorizeAIClinicalUse({ ...model, evaluationPassed: false }, 'summarization').allowed) throw new Error('Unevaluated AI model authorized');
  if (!ai.authorizeAIClinicalUse(model, 'unregistered-use').allowed === false) throw new Error('');
  if (ai.authorizeAIClinicalUse(model, 'diagnosis').allowed) throw new Error('Prohibited AI use authorized');
  if (!ai.authorizeAIClinicalUse(model, 'unregistered-use').allowed === false) throw new Error('Unregistered AI use authorized');
  if (ai.governClinicalOutput(model, output).review !== 'required') throw new Error('Low-confidence AI output did not escalate');
  expectThrow(() => ai.governClinicalOutput(model, { ...output, intendedUse: 'diagnosis' }), 'Prohibited AI output was governed as safe');
  expectThrow(() => ai.governClinicalOutput({ ...model, lifecycle: 'restricted' }, output), 'Restricted AI model produced governed output');

  const prefs = { preferredLanguage: 'en', preferredChannels: ['sms'], appointmentReminders: true, medicationReminders: true, resultNotifications: true, marketingMessages: false, quietHours: { start: '22:00', end: '07:00' } };
  const quiet = communication.evaluateCommunicationRequest(prefs, { category: 'appointment', channel: 'sms', now: new Date('2026-01-01T23:00:00') });
  if (quiet.allowed) throw new Error('Quiet-hours communication permitted');
  const marketing = communication.evaluateCommunicationRequest(prefs, { category: 'marketing', channel: 'sms' });
  if (marketing.allowed) throw new Error('Unconsented marketing communication permitted');
  const wrongChannel = communication.evaluateCommunicationRequest(prefs, { category: 'appointment', channel: 'email' });
  if (wrongChannel.allowed) throw new Error('Unconsented channel permitted');
  const operational = communication.evaluateCommunicationRequest(prefs, { category: 'operational', channel: 'sms', language: 'tw', containsSensitiveData: true });
  if (!operational.allowed || operational.language !== 'tw' || !operational.minimumNecessary) throw new Error('Operational minimum-necessary communication policy failed');
  const emergency = communication.evaluateCommunicationRequest(prefs, { category: 'emergency', channel: 'email', emergency: true });
  if (emergency.allowed) throw new Error('Emergency override bypassed channel authorization');
  const emergencyAllowed = communication.evaluateCommunicationRequest({ ...prefs, emergencyOverrideAllowed: true }, { category: 'emergency', channel: 'email', emergency: true, containsSensitiveData: true });
  if (!emergencyAllowed.allowed || !emergencyAllowed.minimumNecessary) throw new Error('Explicit emergency override was rejected');
  const malformedQuiet = communication.evaluateCommunicationRequest({ ...prefs, quietHours: { start: 'invalid', end: '07:00' } }, { category: 'appointment', channel: 'sms' });
  if (!malformedQuiet.allowed) throw new Error('Malformed quiet-hours configuration unexpectedly blocked communication');

  const activeProfile = {
    profileKey: 'gh', countryCode: 'GH', regionCode: 'GH-AA', locale: 'en-GH', timezone: 'Africa/Accra', currencyCode: 'GHS',
    dataResidencyRegion: 'GH', regulatoryProfile: 'ghana', clinicalProfile: 'default', communicationProfile: 'default',
    accessibilityProfile: 'wcag-2.2-aa', securityProfile: 'zero-trust', enabledModules: ['appointments'],
    effectiveFrom: '2026-01-01T00:00:00.000Z', effectiveTo: '2027-01-01T00:00:00.000Z',
  };
  const source = { findActive: () => activeProfile };
  const profile = deployment.resolveDeploymentProfile(source, 'gh', new Date('2026-06-01T00:00:00Z'));
  if (!deployment.isModuleAllowed(profile, 'appointments')) throw new Error('Enabled deployment module denied');
  if (deployment.isModuleAllowed(profile, 'pharmacy')) throw new Error('Disabled deployment module allowed');
  expectThrow(() => deployment.resolveDeploymentProfile(source, 'gh', new Date('2025-12-01T00:00:00Z')), 'Expired/inactive deployment profile accepted');
  expectThrow(() => deployment.resolveDeploymentProfile({ findActive: () => undefined }, 'gh', new Date()), 'Missing deployment profile accepted');

  for (const context of [
    { authorised: false, confirmed: true, audited: true, online: true },
    { authorised: true, confirmed: false, audited: true, online: true },
    { authorised: true, confirmed: true, audited: false, online: true },
    { authorised: true, confirmed: true, audited: true, online: false },
  ]) {
    expectThrow(() => guards.guardClinicalAction('medication-administration', context), 'Unsafe clinical action permitted');
  }
  clinical.assertClinicalActionSafe('medication-administration', { authorised: true, confirmed: true, audited: true, online: true });
  expectThrow(() => guards.guardAIOutput({ model: model.modelKey, version: model.version, intendedUse: 'summarization', authorised: true, evaluationPassed: true }, { ...output, confidence: 0.5 }), 'Low-confidence AI output guard failed to escalate');
  expectThrow(() => guards.guardAIOutput({ model: model.modelKey, version: model.version, intendedUse: 'summarization', authorised: false, evaluationPassed: true }, output), 'Unauthorized AI output permitted');
  expectThrow(() => guards.guardDeploymentModule({ findActive: () => activeProfile }, 'gh', 'pharmacy', new Date('2026-06-01T00:00:00Z')), 'Disabled deployment module permitted');
  expectThrow(() => guards.guardCommunication(prefs, { category: 'marketing', channel: 'sms' }), 'Unconsented communication permitted by runtime guard');

  console.log('Next-gen runtime, interoperability, AI governance, communication, deployment, and clinical safety tests passed.');
} finally {
  rmSync(temp, { recursive: true, force: true });
}
