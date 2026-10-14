import assert from 'node:assert/strict';
import fs from 'node:fs';

const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const workflow = fs.readFileSync('.github/workflows/diagnostic-integrity.yml', 'utf8');
const packageScripts = packageJson.scripts ?? {};
const runCommands = [...workflow.matchAll(/^\s+run: npm run ([a-zA-Z0-9:_-]+)\s*$/gm)].map((match) => match[1]);

assert.ok(runCommands.length > 0, 'diagnostic workflow must execute npm scripts');
for (const name of runCommands) {
  assert.ok(packageScripts[name], `Diagnostic workflow references missing npm script: ${name}`);
}

const nodeCommands = [...workflow.matchAll(/^\s+run: node ([^\s]+)\s*$/gm)].map((match) => match[1]);
for (const file of nodeCommands) {
  assert.ok(fs.existsSync(file), `Diagnostic workflow references missing Node contract: ${file}`);
}

const migrationDir = 'supabase/migrations';
const migrations = fs.readdirSync(migrationDir).filter((name) => /^\d{14}_.+\.sql$/.test(name));
const versions = new Map();
for (const name of migrations) {
  const version = name.slice(0, 14);
  assert.ok(!versions.has(version), `Duplicate migration version ${version}: ${versions.get(version)} and ${name}`);
  versions.set(version, name);
}

console.log(`[diagnostic-ci-contract] ${runCommands.length} npm scripts, ${nodeCommands.length} Node contracts, and ${migrations.length} unique migration versions verified`);
