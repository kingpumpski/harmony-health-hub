const BASE_PATH = '/harmony-health-hub';
const CACHE_NAME = 'harmony-health-hub-shell-v11';
const SHELL = [
  `${BASE_PATH}/`,
  `${BASE_PATH}/index.html`,
  `${BASE_PATH}/manifest.webmanifest`,
];
const PRODUCTION_MANIFEST = `${BASE_PATH}/.vite/manifest.json`;
const NETWORK_ONLY_PATHS = new Set([
  `${BASE_PATH}/`,
  `${BASE_PATH}/index.html`,
  `${BASE_PATH}/sw.js`,
  `${BASE_PATH}/manifest.webmanifest`,
  PRODUCTION_MANIFEST,
]);

async function cacheRequiredShell(cache) {
  for (const path of SHELL) {
    try {
      const response = await fetch(path, { cache: 'no-store' });
      if (response.ok) await cache.put(path, response.clone());
    } catch {
      // A temporary Pages/network failure must not abort service-worker install.
    }
  }
}

async function precacheProductionAssets(cache) {
  try {
    const manifestResponse = await fetch(PRODUCTION_MANIFEST, { cache: 'no-store' });
    if (!manifestResponse.ok) return;
    const manifest = await manifestResponse.json();
    const assets = new Set([`${BASE_PATH}/index.html`]);
    const visit = (entry, visited = new Set()) => {
      if (!entry || typeof entry !== 'object' || visited.has(entry)) return;
      visited.add(entry);
      const add = (file) => {
        if (typeof file === 'string') assets.add(file.startsWith('/') ? `${BASE_PATH}${file}` : `${BASE_PATH}/${file}`);
      };
      add(entry.file);
      if (Array.isArray(entry.css)) entry.css.forEach(add);
      if (Array.isArray(entry.assets)) entry.assets.forEach(add);
      if (Array.isArray(entry.imports)) entry.imports.forEach((key) => visit(manifest[key], visited));
      if (Array.isArray(entry.dynamicImports)) entry.dynamicImports.forEach((key) => visit(manifest[key], visited));
    };
    visit(manifest['index.html']);
    await Promise.allSettled([...assets].filter((asset) => !NETWORK_ONLY_PATHS.has(asset)).map(async (asset) => {
      try {
        const response = await fetch(asset, { cache: 'no-store' });
        if (response.ok) await cache.put(asset, response.clone());
      } catch {
        // Optional hashed assets are cached on first successful runtime request.
      }
    }));
  } catch {
    // Shell installation remains resilient if the manifest is unavailable.
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cacheRequiredShell(cache);
    await precacheProductionAssets(cache);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin || !url.pathname.startsWith(BASE_PATH)) return;

  if (NETWORK_ONLY_PATHS.has(url.pathname)) {
    event.respondWith(fetch(request, { cache: 'no-store' }));
    return;
  }

  if (url.pathname.startsWith(`${BASE_PATH}/assets/`)) {
    event.respondWith(fetch(request, { cache: 'no-store' }).then((response) => {
      if (response.ok) void caches.open(CACHE_NAME).then((cache) => cache.put(request, response.clone())).catch(() => undefined);
      return response;
    }).catch(() => caches.match(request).then((cached) => cached ?? Response.error())));
    return;
  }

  event.respondWith(fetch(request).then((response) => {
    if (response.ok) void caches.open(CACHE_NAME).then((cache) => cache.put(request, response.clone())).catch(() => undefined);
    return response;
  }).catch(() => caches.match(request).then((cached) => cached ?? (request.mode === 'navigate' ? caches.match(`${BASE_PATH}/index.html`) : Response.error()))));
});
