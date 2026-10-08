import fs from 'node:fs';
import assert from 'node:assert/strict';

const fallback = fs.readFileSync('public/404.html', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');

assert.match(fallback, /window\.location\.replace/);
assert.match(fallback, /encodeURIComponent/);
assert.match(fallback, /window\.location\.pathname/);
assert.match(index, /new URLSearchParams\(window\.location\.search\)/);
assert.match(index, /params\.get\(['"]route['"]\)/);
assert.match(index, /history\.replaceState/);

console.log('GitHub Pages BrowserRouter deep-link fallback contract passed.');
