import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const root = process.cwd();
const temp = mkdtempSync(join(tmpdir(), 'harmony-nextgen-'));

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

  const validEnvelope = {
    messageId: 'msg-1', correlationId: 'corr-1', sourceSystem: 'test-source',
    destinationSystem: 'harmony', standard: 'FHIR_R4', direction: 'inbound',
    eventType: 'Patient.updated', schemaVersion: '1.0', occurredAt: new Date().toISOString(),
    classification: 'clinical', payload: { id: 'p1' },
  };
  const store = new Map();
  const runtimeStore = { find: (id) => store.get(id), enqueue: (record) => store.set(record.messageId, record) };

  if (!contracts.validateEnvelope(validEnvelope)) throw new Error('Valid FHIR envelope rejected');
  if (contracts.validateEnvelope({ ...validEnvelope, standard: 'NOT_A_STANDARD' })) throw new Error('Unsupported standard accepted');
  if (contracts.validateEnvelope({ ...validEnvelope, occurredAt: 'not-a-date' })) throw new Error('Invalid timestamp accepted');
  if (integration.evaluateIncomingEnvelope(validEnvelope, runtimeStore).decision !== 'accept') throw new Error('First envelope not accepted');
  if (integration.evaluateIncomingEnvelope(validEnvelope, runtimeStore).decision !== 'duplicate') throw new Error('Duplicate envelope not rejected');

  const retry = integration.nextRetry({ messageId: 'm', correlationId: 'c', state: 'failed', attemptCount: 1 });
  if (retry.state !== 'failed' || !retry.nextAttemptAt) throw new Error('Retry scheduling failed');
  const quarantined = integration.nextRetry({ messageId: 'm', correlationId: 'c', state: 'failed', attemptCount: 5 });
  if (quarantined.state !== 'quarantined') throw new Error('Maximum-attempt quarantine failed');
  if (integration.canReplay(quarantined, { authorised: false, confirmed: true })) throw new Error('Unauthorized replay permitted');
  if (!integration.canReplay(quarantined, { authorised: true, confirmed: true })) throw new Error('Authorized replay rejected');

  const model = { modelKey: 'test-model', version: '1', lifecycle: 'active', intendedUses: ['summarization'], prohibitedUses: ['diagnosis'], evaluationPassed: true, evidenceReferences: ['eval-1'] };
  const output = { requestId: 'r1', modelKey: 'test-model', modelVersion: '1', intendedUse: 'summarization', confidence: 0.84, evidence: [{ source: 'record' }], review: 'not-required', output: 'summary', generatedAt: new Date().toISOString() };
  if (ai.authorizeAIClinicalUse({ ...model, lifecycle: 'suspended' }, 'summarization').allowed) throw new Error('Suspended AI model authorized');
  if (ai.authorizeAIClinicalUse({ ...model, evaluationPassed: false }, 'summarization').allowed) throw new Error('Unevaluated AI model authorized');
  if (ai.authorizeAIClinicalUse(model, 'diagnosis').allowed) throw new Error('Prohibited AI use authorized');
  if (ai.governClinicalOutput(model, output).review !== 'required') throw new Error('Low-confidence AI output did not escalate');

  const prefs = { preferredLanguage: 'en', preferredChannels: ['sms'], appointmentReminders: true, medicationReminders: true, resultNotifications: true, marketingMessages: false, quietHours: { start: '22:00', end: '07:00' } };
  const quiet = communication.evaluateCommunicationRequest(prefs, { category: 'appointment', channel: 'sms', now: new Date('2026-01-01T23:00:00') });
  if (quiet.allowed) throw new Error('Quiet-hours communication permitted');
  const marketing = communication.evaluateCommunicationRequest(prefs, { category: 'marketing', channel: 'sms' });
  if (marketing.allowed) throw new Error('Unconsented marketing communication permitted');
  const emergency = communication.evaluateCommunicationRequest(prefs, { category: 'emergency', channel: 'email', emergency: true });
  if (emergency.allowed) throw new Error('Emergency override bypassed channel authorization');

  const source = { findActive: () => ({ profileKey: 'gh', countryCode: 'GH', regionCode: 'GH-AA', locale: 'en-GH', timezone: 'Africa/Accra', currencyCode: 'GHS', dataResidencyRegion: 'GH', regulatoryProfile: 'ghana', clinicalProfile: 'default', communicationProfile: 'default', accessibilityProfile: 'wcag-2.2-aa', securityProfile: 'zero-trust', enabledModules: ['appointments'] }) };
  const profile = deployment.resolveDeploymentProfile(source, 'gh', new Date());
  if (!deployment.isModuleAllowed(profile, 'appointments')) throw new Error('Enabled deployment module denied');
  if (deployment.isModuleAllowed(profile, 'pharmacy')) throw new Error('Disabled deployment module allowed');

  for (const context of [{ authorised: false, confirmed: true, online: true }, { authorised: true, confirmed: false, online: true }]) {
    try { guards.guardClinicalAction('medication-administration', context); throw new Error('Unsafe clinical action permitted'); } catch (error) {
      if (error.message === 'Unsafe clinical action permitted') throw error;
    }
  }
  clinical.assertClinicalActionSafe('medication-administration', { authorised: true, confirmed: true, online: true });

  console.log('Next-gen runtime contract tests passed.');
} finally {
  rmSync(temp, { recursive: true, force: true });
}
