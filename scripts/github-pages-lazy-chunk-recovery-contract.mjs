import fs from 'node:fs';

const app = fs.readFileSync('src/App.tsx', 'utf8');
const helper = fs.readFileSync('src/lib/lazyWithChunkRecovery.ts', 'utf8');
const pages = fs.readFileSync('.github/workflows/pages.yml', 'utf8');

for (const needle of [
  "import { lazyWithChunkRecovery } from '@/lib/lazyWithChunkRecovery';",
  'lazyWithChunkRecovery(() => import(',
]) {
  if (!app.includes(needle)) throw new Error('App is missing lazy chunk recovery wiring: ' + needle);
}

for (const needle of [
  'Failed to fetch dynamically imported module',
  '__hms_chunk_recovery',
  'sessionStorage',
  'window.location.replace',
]) {
  if (!helper.includes(needle)) throw new Error('Lazy chunk recovery is missing: ' + needle);
}

for (const needle of [
  'actions/upload-pages-artifact@v4',
  'actions/deploy-pages@v4',
  'path: ./dist',
]) {
  if (!pages.includes(needle)) throw new Error('GitHub Pages deployment contract changed: ' + needle);
}

console.log('GitHub Pages lazy-chunk recovery contract passed.');
