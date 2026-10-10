import fs from 'node:fs';
import assert from 'node:assert/strict';

const source = fs.readFileSync('src/pages/PatientPortal.tsx', 'utf8');
assert.match(source, /useEffect, useRef, useState/);
assert.match(source, /const loadVersion = useRef\(0\)/);
assert.match(source, /const version = \+\+loadVersion\.current/);
assert.match(source, /if \(version !== loadVersion\.current\) return null;/);
assert.match(source, /if \(!user\) \{[\s\S]*?setPatient\(null\);[\s\S]*?setClinicalSnapshot\(null\);[\s\S]*?setUnavailableSections\(\[\]\);/);
assert.match(source, /return \(\) => \{ loadVersion\.current \+= 1; \};/);
const requestBatch = source.indexOf('const requests = await Promise.allSettled([');
const staleGuard = source.indexOf('if (version !== loadVersion.current) return null;', requestBatch);
const stateWrite = source.indexOf('setPatient(portalPatient)', requestBatch);
assert.ok(requestBatch >= 0 && staleGuard > requestBatch && stateWrite > staleGuard,
  'A stale patient data batch must be discarded before any portal state is written.');
console.log('Patient portal stale-identity request contract passed.');
