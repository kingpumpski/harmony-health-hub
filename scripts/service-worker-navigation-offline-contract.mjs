import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync('public/sw.js', 'utf8');
assert.match(source, /harmony-health-hub-shell-v18/, 'service-worker cache version must change when fallback semantics change');
assert.match(source, /response\.status !== 404 && response\.status < 500/, 'navigation must recover from hosting 5xx responses');
assert.match(source, /caches\.match\(\x60\$\{BASE_PATH\}\/index\.html\x60\)/, 'navigation must use the cached SPA shell as a fallback');
assert.doesNotMatch(source, /const genericCacheFallback =/, 'arbitrary GET response caching must not be reintroduced');

function makeWorker(fetchImpl, cachedShell) {
  const listeners = new Map();
  const cache = { put: async () => undefined };
  const context = {
    self: {
      location: { origin: 'https://example.github.io' },
      clients: { claim: async () => undefined },
      skipWaiting: async () => undefined,
      addEventListener: (name, handler) => listeners.set(name, handler),
    },
    caches: {
      open: async () => cache,
      keys: async () => ['harmony-health-hub-shell-v17'],
      delete: async () => true,
      match: async (key) => String(key).endsWith('/index.html') ? cachedShell?.clone() ?? null : null,
    },
    fetch: fetchImpl,
    URL,
    Response,
    Promise,
    Set,
  };
  vm.runInNewContext(source, context, { filename: 'public/sw.js' });
  return listeners.get('fetch');
}

async function requestNavigation(fetchImpl, cachedShell) {
  let responsePromise;
  const handler = makeWorker(fetchImpl, cachedShell);
  handler({
    request: {
      method: 'GET',
      mode: 'navigate',
      url: 'https://example.github.io/harmony-health-hub/radiology',
    },
    respondWith: (promise) => { responsePromise = promise; },
  });
  assert.ok(responsePromise, 'navigation request should be intercepted');
  return responsePromise;
}

const networkShell = '<!doctype html><title>Harmony Health Hub</title>';
const onlineFallback = await requestNavigation(async (input) => {
  const url = typeof input === 'string' ? input : input.url;
  if (url.endsWith('/radiology')) return new Response('hosting unavailable', { status: 503 });
  if (url.endsWith('/index.html')) return new Response(networkShell, { status: 200 });
  throw new Error('Unexpected request: ' + url);
}, null);
assert.equal(onlineFallback.status, 200, 'a route 503 should fall back to the network SPA shell');
assert.match(await onlineFallback.text(), /Harmony Health Hub/);

const cachedShell = new Response('<!doctype html><title>Cached Harmony Health Hub</title>', { status: 200 });
const offlineFallback = await requestNavigation(async () => { throw new TypeError('offline'); }, cachedShell);
assert.equal(offlineFallback.status, 200, 'offline deep links should fall back to the cached SPA shell');
assert.match(await offlineFallback.text(), /Cached Harmony Health Hub/);

console.log('Service-worker navigation fallback contract passed: 503 recovery, network-offline cached shell, and cache-version invalidation.');
