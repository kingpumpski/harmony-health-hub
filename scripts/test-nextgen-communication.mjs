import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const root = process.cwd();
const temp = mkdtempSync(join(tmpdir(), 'harmony-nextgen-communication-'));

try {
  execFileSync(
    process.platform === 'win32' ? 'npx.cmd' : 'npx',
    ['tsc', '--target', 'ES2022', '--module', 'commonjs', '--moduleResolution', 'node', '--skipLibCheck', '--esModuleInterop', '--outDir', temp, join(root, 'src/lib/nextGenCommunicationPolicy.ts')],
    { cwd: root, stdio: 'inherit' },
  );

  const require = createRequire(import.meta.url);
  const communication = require(join(temp, 'nextGenCommunicationPolicy.js'));
  const base = {
    preferredLanguage: 'en',
    preferredChannels: ['sms'],
    appointmentReminders: true,
    medicationReminders: true,
    resultNotifications: true,
    marketingMessages: false,
  };

  const nyQuietHours = { start: '22:00', end: '07:00', timezone: 'America/New_York' };
  const quiet = communication.evaluateCommunicationRequest(
    { ...base, quietHours: nyQuietHours },
    { category: 'appointment', channel: 'sms', now: new Date('2026-01-02T04:00:00.000Z') },
  );
  if (quiet.allowed) throw new Error('Timezone-aware quiet hours permitted a blocked communication');

  const outside = communication.evaluateCommunicationRequest(
    { ...base, quietHours: nyQuietHours },
    { category: 'appointment', channel: 'sms', now: new Date('2026-01-02T15:00:00.000Z') },
  );
  if (!outside.allowed) throw new Error('Timezone-aware quiet hours blocked an allowed communication');

  const invalidTimezone = communication.evaluateCommunicationRequest(
    { ...base, quietHours: { start: '22:00', end: '07:00', timezone: 'Not/A/Timezone' } },
    { category: 'appointment', channel: 'sms' },
  );
  if (invalidTimezone.allowed || invalidTimezone.reason !== 'Invalid quiet-hours configuration') {
    throw new Error('Invalid timezone did not fail closed');
  }

  const invalidChannel = communication.evaluateCommunicationRequest(
    { ...base },
    { category: 'appointment', channel: 'carrier-pigeon' },
  );
  if (invalidChannel.allowed || invalidChannel.reason !== 'Unsupported communication channel') {
    throw new Error('Unsupported communication channel did not fail closed');
  }

  const invalidCategory = communication.evaluateCommunicationRequest(
    { ...base },
    { category: 'diagnosis', channel: 'sms' },
  );
  if (invalidCategory.allowed || invalidCategory.reason !== 'Unsupported communication category') {
    throw new Error('Unsupported communication category did not fail closed');
  }

  const invalidTimestamp = communication.evaluateCommunicationRequest(
    { ...base },
    { category: 'appointment', channel: 'sms', now: new Date('invalid') },
  );
  if (invalidTimestamp.allowed || invalidTimestamp.reason !== 'Invalid communication timestamp') {
    throw new Error('Invalid communication timestamp did not fail closed');
  }

  const invalidLanguage = communication.evaluateCommunicationRequest(
    { ...base },
    { category: 'appointment', channel: 'sms', language: '   ' },
  );
  if (invalidLanguage.allowed || invalidLanguage.reason !== 'Invalid communication language') {
    throw new Error('Blank communication language did not fail closed');
  }

  const emergencyWithoutContext = communication.evaluateCommunicationRequest(
    { ...base, emergencyOverrideAllowed: true },
    { category: 'emergency', channel: 'email', emergency: false },
  );
  if (emergencyWithoutContext.allowed) throw new Error('Emergency category bypassed explicit emergency context');

  const emergencyWithOverride = communication.evaluateCommunicationRequest(
    { ...base, emergencyOverrideAllowed: true },
    { category: 'emergency', channel: 'email', emergency: true, containsSensitiveData: true },
  );
  if (!emergencyWithOverride.allowed || !emergencyWithOverride.minimumNecessary) {
    throw new Error('Authorized emergency override was rejected or not marked minimum-necessary');
  }

  console.log('Next-gen communication input, timezone and emergency boundary tests passed.');
} finally {
  rmSync(temp, { recursive: true, force: true });
}
