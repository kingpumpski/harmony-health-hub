#!/usr/bin/env node
import fs from 'node:fs';

const checks = [
  ['src/pages/ReviewAppointmentQueue.tsx', "rpc('get_pending_review_appointments', {})"],
  ['src/pages/SpecialistReferralQueue.tsx', "rpc('get_pending_specialist_referrals', {})"],
];

for (const [file, token] of checks) {
  const source = fs.readFileSync(file, 'utf8');
  if (!source.includes(token)) throw new Error(file + ' must use standard POST transport for its referral queue read');
}
console.log('Stable referral queue transport contract passed');


const specialistQueue = fs.readFileSync('src/pages/SpecialistReferralQueue.tsx', 'utf8');
for (const token of [
  'function toLocalDateTimeInput(value: string | Date)',
  'date.getFullYear()',
  'date.getHours()',
  "min={toLocalDateTimeInput(new Date())}",
  "toLocalDateTimeInput(row.appointment_date??'')",
]) {
  if (!specialistQueue.includes(token)) throw new Error('Specialist appointment input must preserve local time and reject past dates: ' + token);
}
if (specialistQueue.includes('new Date(row.appointment_date).toISOString().slice(0,16)')) {
  throw new Error('UTC conversion must not be used to populate a local datetime-local input');
}
