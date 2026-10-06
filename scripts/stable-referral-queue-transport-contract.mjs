#!/usr/bin/env node
import fs from 'node:fs';

const checks = [
  ['src/pages/ReviewAppointmentQueue.tsx', "rpc('get_pending_review_appointments', {}, { get: true })"],
  ['src/pages/SpecialistReferralQueue.tsx', "rpc('get_pending_specialist_referrals', {}, { get: true })"],
];

for (const [file, token] of checks) {
  const source = fs.readFileSync(file, 'utf8');
  if (!source.includes(token)) throw new Error(file + ' must use GET transport for its stable referral queue read');
}
console.log('Stable referral queue transport contract passed');
