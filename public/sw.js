const CACHE_NAME = 'harmony-health-hub-shell-v3';
const APP_SHELL = ['/', '/index.html', '/manifest.webmanifest', '/.vite/manifest.json'];

async function precacheProductionAssets() {
  const cache = await caches.open(CACHE_NAME);
  await cache.addAll(APP_SHELL);

  try {
    const manifestResponse = await fetch('/.vite/manifest.json', { cache: 'no-store' });
    if (!manifestResponse.ok) return;

    const manifest = await manifestResponse.json();
    const assets = new Set(['/index.html']);

    const visit = (entry) => {
      if (!entry || typeof entry !== 'object') return;
      if (typeof entry.file === 'string') assets.add(`/${entry.file}`);
      if (Array.isArray(entry.css)) {
        entry.css.filter((file) => typeof file === 'string').forEach((file) => assets.add(`/${file}`));
      }
      if (Array.isArray(entry.assets)) {
        entry.assets.filter((file) => typeof file === 'string').forEach((file) => assets.add(`/${file}`));
      }
      if (Array.isArray(entry.imports)) {
        entry.imports.forEach((key) => visit(manifest[key]));
      }
      if (Array.isArray(entry.dynamicImports)) {
        entry.dynamicImports.forEach((key) => visit(manifest[key]));
      }
    };

    Object.values(manifest).forEach(visit);

    await Promise.allSettled(
      [...assets].map(async (asset) => {
        try {
          const response = await fetch(asset, { cache: 'no-store' });
          if (response.ok) await cache.put(asset, response.clone());
        } catch {
          // A single optional asset must not prevent the application shell
          // from becoming available offline.
        }
      })
    );
  } catch {
    // Runtime caching remains the fallback when the production manifest is
    // unavailable during installation.
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil(precacheProductionAssets().then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    fetch(request)
      .then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
        }
        return response;
      })
      .catch(() => caches.match(request).then((cached) => {
        if (cached) return cached;
        if (request.mode === 'navigate') return caches.match('/index.html');
        return Response.error();
      }))
  );
});
