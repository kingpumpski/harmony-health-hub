import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const fail = (message) => {
  console.error(`Local repository check failed: ${message}`);
  process.exitCode = 1;
};

try {
  const gitRoot = execFileSync('git', ['rev-parse', '--show-toplevel'], {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
  if (resolve(gitRoot) !== root) fail(`Git root is ${gitRoot}, expected ${root}`);
} catch {
  fail('Git is not available or this project folder is not a Git working tree. Open the repository root, not a parent/subfolder.');
}

for (const file of ['package.json', 'package-lock.json']) {
  if (!existsSync(resolve(root, file))) fail(`missing ${file}`);
}

const packageJson = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
if (!packageJson.scripts?.dev) fail('package.json does not define the dev script.');

if (!existsSync(resolve(root, 'node_modules/.bin/vite'))) {
  console.error('Dependencies are not installed. Run npm ci from the repository root.');
  process.exitCode = 1;
}

if (process.exitCode) process.exit(process.exitCode);
console.log(`Repository root verified: ${root}`);
console.log('Git working tree and npm dependency prerequisites are ready.');
