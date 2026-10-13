import assert from 'node:assert/strict';
import fs from 'node:fs';

const configPath = '.devcontainer/devcontainer.json';
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const qualityWorkflow = fs.readFileSync('.github/workflows/quality.yml', 'utf8');

assert.equal(
  config.image,
  'mcr.microsoft.com/devcontainers/base:bookworm',
  'Codespaces must use the standard Bookworm base image that provides the vscode account',
);

assert.equal(
  config.remoteUser,
  'vscode',
  'remoteUser must match the account supplied by the configured base image',
);

assert.equal(
  config.features?.['ghcr.io/devcontainers/features/node:1']?.version,
  '24',
  'Codespaces Node.js must match the Node 24 CI runtime',
);

assert.ok(
  Array.isArray(config.forwardPorts) && config.forwardPorts.includes(5173),
  'Codespaces must forward Vite default port 5173',
);

assert.ok(
  config.portsAttributes?.['5173'],
  'Forwarded Vite port must have a visible port attribute',
);

assert.equal(
  config.postCreateCommand,
  'npm ci',
  'Codespaces dependency installation must use the lockfile',
);

assert.equal(
  packageJson.scripts?.dev,
  'vite',
  'The expected Vite development server script must remain available',
);

assert.match(
  qualityWorkflow,
  /NODE_VERSION:\s*24/,
  'The Quality workflow Node version must stay aligned with the devcontainer',
);

console.log('Devcontainer configuration contract passed.');
