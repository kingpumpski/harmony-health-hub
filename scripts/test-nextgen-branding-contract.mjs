import fs from 'node:fs';

const html = fs.readFileSync('index.html', 'utf8');
const manifest = fs.readFileSync('public/manifest.webmanifest', 'utf8');

const requiredHtmlMarkers = [
  '<title>Harmony Health Hub | Healthcare Information Management</title>',
  'content="Harmony Health Hub"',
  'content="Secure, interoperable healthcare information management for hospitals, clinics, and care teams."',
  '<link rel="manifest" href="/manifest.webmanifest" />',
  '<meta name="apple-mobile-web-app-title" content="Harmony Health Hub" />',
];

for (const marker of requiredHtmlMarkers) {
  if (!html.includes(marker)) throw new Error(`Branding metadata contract missing: ${marker}`);
}

for (const legacyMarker of ['MediCare Pro', 'medicare-pro.lovable.app', 'lovable.dev/opengraph-image']) {
  if (html.includes(legacyMarker)) throw new Error(`Legacy/third-party branding metadata remains: ${legacyMarker}`);
}

if (!manifest.includes('"name": "Harmony Health Hub"')) {
  throw new Error('PWA manifest name is not aligned with Harmony Health Hub');
}
if (!manifest.includes('"short_name": "Harmony Health"')) {
  throw new Error('PWA manifest short name is not aligned with Harmony Health');
}

console.log('Next-gen branding contract passed: application metadata, PWA identity, and legacy-host removal are aligned with Harmony Health Hub.');
