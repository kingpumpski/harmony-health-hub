import assert from 'node:assert/strict';
import fs from 'node:fs';

const replay = fs.readFileSync('.github/workflows/migration-contract.yml', 'utf8');
const deploy = fs.readFileSync('.github/workflows/supabase-migrations.yml', 'utf8');
const quality = fs.readFileSync('.github/workflows/quality.yml', 'utf8');
const stepFor = (source, command) => source.split(/\n\s+- /).find(step => step.includes(command)) ?? '';
assert.match(replay, /run: npm run test:migration-contract/, 'static migration validation is mandatory');
assert.doesNotMatch(stepFor(replay, 'run: npm run test:migration-contract'), /\bif:/, 'missing static contracts must fail, not skip');
assert.match(replay, /run: supabase test db supabase\/tests\/database\s*$/, 'clean replay must test every existing SQL contract, including laboratory and security');
assert.doesNotMatch(stepFor(replay, 'run: supabase test db supabase/tests/database'), /\bif:/, 'runtime contracts must never silently skip');
assert.ok(replay.indexOf('run: node scripts/migration-contract.mjs') < replay.indexOf('if supabase start'), 'conflicting versions must stop replay before services start');
assert.match(replay, /run: supabase db reset/, 'full clean replay must remain enabled');
assert.match(replay, /branches: \[main\]/, 'main-target pull requests must run migration checks');
assert.match(replay, /'scripts\/migration-\*\.mjs'/, 'validator changes must trigger migration CI');

const facilityBoundaryPath = 'supabase/tests/database/facility_boundary_workspace_contract.sql';
const facilityBoundary = fs.readFileSync(facilityBoundaryPath, 'utf8');
assert.match(deploy, /supabase test db --linked supabase\/tests\/database\/facility_boundary_workspace_contract\.sql/, 'facility-boundary regression must run in hosted verification and apply modes');
assert.match(facilityBoundary, /SELECT plan\(12\);/, 'facility-boundary contract must include the platform-admin regression assertion');
assert.match(facilityBoundary, /v_platform_admin:=v_rolein\(''it_admin'',''system_superuser''\)/, 'platform bypass assertion must exclude facility-scoped admin');
assert.match(facilityBoundary, /facility admin is not treated as a platform-wide bypass/, 'facility-admin bypass regression must remain explicitly named');
assert.match(facilityBoundary, /appointment reads require active-facility lineage unless an explicit platform administrator has no facility selected/, 'appointment facility-null bypass regression must remain explicit');
assert.match(facilityBoundary, /ward and bed reads exclude unassigned facility rows for ordinary callers/, 'unassigned ward/bed bypass regression must remain explicit');


assert.match(deploy, /environment: production/, 'all linked production database operations must pass through the protected production environment');
assert.match(deploy, /uses: actions\/setup-node@v5/, 'deployment validation requires a known Node runtime');
assert.ok(deploy.indexOf('run: npm ci') > 0 && deploy.indexOf('run: npm ci') < deploy.indexOf('run: npm run test:project-integrity'), 'dependencies must be installed before integrity checks');
assert.ok(deploy.indexOf('run: npm run test:migration-contract') < deploy.indexOf('run: supabase link'), 'missing contracts must block linking');
assert.match(quality, /\n  quality:\n/, 'stable mandatory quality job identity must be preserved');
assert.match(quality, /run: npm run test:migration-parity/, 'validator regressions must run in the quality gate');
assert.match(quality, /run: npm run test:migration-contract/, 'migration contract cannot be omitted from the quality gate');
assert.match(stepFor(quality, 'run: npm run test:migration-contract'), /continue-on-error: true/, 'legacy migration blockers must be reported without suppressing unrelated application quality checks');

const productionApply = deploy.indexOf('run: supabase db push --linked', deploy.indexOf('name: Apply migrations'));
const productionPreflight = deploy.indexOf('name: Preflight migration plan before validation or production apply');
assert.ok(productionPreflight >= 0, 'production apply must have a migration dry-run preflight');
assert.ok(productionPreflight < deploy.indexOf('name: Apply migrations'), 'migration preflight must precede production apply');
assert.ok(deploy.slice(productionPreflight, deploy.indexOf('name: Require explicit production apply confirmation')).includes("inputs.mode == 'validate' || inputs.mode == 'apply'"), 'dry-run must execute in both validate and apply modes');
assert.ok(productionApply >= 0, 'production apply command must remain explicitly identifiable');

console.log('[migration-contract-workflow-regression] mandatory validation, complete database test coverage, and dependency setup passed');