const CACHE_NAME = 'harmony-health-hub-shell-v4';
const REQUIRED_SHELL = ['/', '/index.html', '/manifest.webmanifest'];
const PRODUCTION_MANIFEST = '/.vite/manifest.json';

async function cacheRequiredShell(cache) {
  await cache.addAll(REQUIRED_SHELL);
}

async function precacheProductionAssets(cache) {
  try {
    const manifestResponse = await fetch(PRODUCTION_MANIFEST, { cache: 'no-store' });
    if (!manifestResponse.ok) return;

    const manifest = await manifestResponse.json();
    const assets = new Set(['/index.html']);

    const visit = (entry, visited = new Set()) => {
      if (!entry || typeof entry !== 'object' || visited.has(entry)) return;
      visited.add(entry);

      if (typeof entry.file === 'string') assets.add(`/${entry.file}`);
      if (Array.isArray(entry.css)) {
        entry.css
          .filter((file) => typeof file === 'string')
          .forEach((file) => assets.add(`/${file}`));
      }
      if (Array.isArray(entry.assets)) {
        entry.assets
          .filter((file) => typeof file === 'string')
          .forEach((file) => assets.add(`/${file}`));
      }
      if (Array.isArray(entry.imports)) {
        entry.imports.forEach((key) => visit(manifest[key], visited));
      }
      if (Array.isArray(entry.dynamicImports)) {
        entry.dynamicImports.forEach((key) => visit(manifest[key], visited));
      }
    };

    Object.values(manifest).forEach((entry) => visit(entry));

    await Promise.allSettled(
      [...assets].map(async (asset) => {
        try {
          const response = await fetch(asset, { cache: 'no-store' });
          if (response.ok) await cache.put(asset, response.clone());
        } catch {
          // Optional hashed assets are retried by the normal runtime cache.
        }
      })
    );

    // Keep the manifest itself available for diagnostics and future installs.
    const manifestCopy = await fetch(PRODUCTION_MANIFEST, { cache: 'no-store' });
    if (manifestCopy.ok) await cache.put(PRODUCTION_MANIFEST, manifestCopy.clone());
  } catch {
    // The application shell remains installable even if the production
    // manifest cannot be reached during this installation.
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      await cacheRequiredShell(cache);
      await precacheProductionAssets(cache);
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_NAME)
            .map((key) => caches.delete(key))
        )
      )
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
      .catch(() =>
        caches.match(request).then((cached) => {
          if (cached) return cached;
          if (request.mode === 'navigate') return caches.match('/index.html');
          return Response.error();
        })
      )
  );
});
