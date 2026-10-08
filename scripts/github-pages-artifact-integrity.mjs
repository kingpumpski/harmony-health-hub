import fs from 'node:fs';
import path from 'node:path';

const dist = path.resolve('dist');
const indexPath = path.join(dist, 'index.html');
const manifestPath = path.join(dist, '.vite', 'manifest.json');

if (!fs.existsSync(indexPath)) throw new Error('GitHub Pages artifact is missing dist/index.html');
if (!fs.existsSync(manifestPath)) throw new Error('GitHub Pages artifact is missing dist/.vite/manifest.json');

const index = fs.readFileSync(indexPath, 'utf8');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

const references = [...index.matchAll(/(?:src|href)="([^"]+)"/g)]
  .map(([, value]) => value)
  .filter((value) => value.startsWith('/harmony-health-hub/assets/'));

const missing = references.filter((value) => {
  const relative = value.replace(/^\/harmony-health-hub\//, '');
  return !fs.existsSync(path.join(dist, relative));
});

if (missing.length) {
  throw new Error('GitHub Pages index references missing assets: ' + missing.join(', '));
}

const manifestAssets = new Set();
for (const entry of Object.values(manifest)) {
  if (!entry || typeof entry !== 'object') continue;
  const record = entry;
  if (typeof record.file === 'string') manifestAssets.add(record.file);
  for (const asset of record.assets ?? []) {
    if (typeof asset === 'string') manifestAssets.add(asset);
  }
  for (const chunk of record.imports ?? []) {
    if (typeof chunk !== 'string') continue;
    const imported = manifest[chunk];
    if (imported?.file) manifestAssets.add(imported.file);
  }
}

const missingManifestAssets = [...manifestAssets].filter((file) => !fs.existsSync(path.join(dist, file)));
if (missingManifestAssets.length) {
  throw new Error('GitHub Pages manifest references missing files: ' + missingManifestAssets.join(', '));
}

console.log(
  `GitHub Pages artifact integrity passed: ${references.length} index assets and ${manifestAssets.size} manifest assets verified.`,
);
