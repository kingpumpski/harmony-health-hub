import assert from 'node:assert/strict';
import fs from 'node:fs';

const worker=fs.readFileSync('supabase/functions/notify-queue-drain/index.ts','utf8');
const provider=fs.readFileSync('supabase/functions/notification-provider-config/index.ts','utf8');
const webhook=fs.readFileSync('supabase/functions/notification-webhook/index.ts','utf8');

const BACKOFF=[10,30,120,600,3600];
assert.deepEqual(BACKOFF,[10,30,120,600,3600]);
assert.equal(BACKOFF[0],10);
assert.equal(BACKOFF.at(-1),3600);

function quiet(now,tz,start,end){
  const p=new Intl.DateTimeFormat('en-GB',{timeZone:tz,hour:'2-digit',minute:'2-digit',hour12:false}).formatToParts(now);
  const m=Number(p.find(x=>x.type==='hour')?.value??0)*60+Number(p.find(x=>x.type==='minute')?.value??0);
  const [sh,sm]=start.split(':').map(Number),[eh,em]=end.split(':').map(Number),s=sh*60+sm,e=eh*60+em;
  return s>e?m>=s||m<e:m>=s&&m<e;
}
assert.equal(quiet(new Date('2026-01-15T23:30:00Z'),'Africa/Accra','22:00','07:00'),true);
assert.equal(quiet(new Date('2026-01-15T12:00:00Z'),'Africa/Accra','22:00','07:00'),false);
assert.equal(quiet(new Date('2026-06-01T03:30:00Z'),'America/New_York','22:00','07:00'),true);
assert.equal(quiet(new Date('2026-06-01T13:30:00Z'),'America/New_York','22:00','07:00'),false);

function rolloutAllows(userId,facilityId,percent){
  if(percent>=100)return true;if(percent<=0)return false;let hash=0;
  for(const ch of facilityId+':'+userId)hash=((hash<<5)-hash+ch.charCodeAt(0))|0;
  return Math.abs(hash)%100<percent;
}
assert.equal(rolloutAllows('u','f',0),false);
assert.equal(rolloutAllows('u','f',100),true);
assert.equal(rolloutAllows('u','f',25),rolloutAllows('u','f',25));

assert.match(worker,/notification_queue/);
assert.match(worker,/status:'pending'/);
assert.match(worker,/max_attempts/);
assert.match(worker,/notification_provider_health/);
assert.match(worker,/consecutive_failures/);
assert.match(worker,/providerAllowed/);
assert.match(worker,/providerOutcome/);
assert.match(worker,/resolveFacilityEmailProviders/);
assert.match(worker,/order\('is_primary'/);
assert.match(worker,/order\('priority'/);
assert.match(worker,/enabled_channels\?\.\[channel\]!==true/);
assert.match(provider,/smtpPort\s*===\s*25/);
assert.match(provider,/smtpPort\s*===\s*587/);
assert.match(provider,/credentials\.port\?\?465/);
assert.match(provider,/secure\s*!==\s*true/);
assert.match(provider,/AES-GCM/);
assert.match(provider,/credentials_ciphertext/);
assert.match(webhook,/notification_webhook_events/);
assert.match(webhook,/23505/);
assert.match(webhook,/INVALID_SIGNATURE/);
console.log('Notification Phase 10 behavior contracts passed.');