import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const appSource = fs.readFileSync(path.join(root, 'src/App.tsx'), 'utf8');
const dist = path.join(root, 'dist');
const index = path.join(dist, 'index.html');
const routes = [...appSource.matchAll(/<Route\s+path="([^"]+)"/g)]
  .map(([, route]) => route)
  .filter((route) => route.startsWith('/') && route !== '/' && !route.includes(':') && route !== '*');

for (const route of routes) {
  const clean = route.replace(/^\/+|\/+$/g, '');
  if (!clean) continue;
  const targetDir = path.join(dist, clean);
  fs.mkdirSync(targetDir, { recursive: true });
  fs.copyFileSync(index, path.join(targetDir, 'index.html'));
}

console.log(`GitHub Pages SPA entrypoints prepared: ${routes.length}`);
