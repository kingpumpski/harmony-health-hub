# npm dependency security audit — 2026-11-27

## Observed CI result

The Quality workflow's `npm audit --audit-level=high` inventory reported **10 vulnerabilities: 8 moderate and 2 high** across 478 installed packages. The workflow intentionally marks this step `continue-on-error: true`, so it is an advisory finding and does not block the Quality build.

Advisories visible in the captured audit output include:
- Zod below 4.6.6 — high severity, GHSA-mrhx-c7xc-m3w5.
- esbuild at or below 0.24.2 — moderate, GHSA-67mh-4wv8-2f99; this affects the current Vite/esbuild dependency chain.
- postcss-selector-parser below 6.1.5 — moderate, GHSA-rj75-hqrm-r3gf.
- React Router 6.0.0 through 7.17.0 — moderate advisories GHSA-wrjc-x8rr-h8h6 and GHSA-337j-9hxr-rhxg.

The captured log summarizes two high findings, but exposes only the Zod high advisory in the excerpted report. The second high advisory must be captured from a complete `npm audit --json` output before claiming its package identity.

## Why no forced upgrade was applied

The audit tool's automatic recommendation crosses multiple major-version boundaries:
- Vite 5 to Vite 8.
- React Router 6 to React Router 7.
- Zod 3 to Zod 4.
- It also proposes a Tailwind typography package downgrade.

Applying `npm audit fix --force` would risk routing, form validation, schema typing and build regressions. No package or lockfile changes were made in this pass.

## Remediation plan

1. Capture a complete machine-readable audit report and identify both high-severity findings.
2. Upgrade Zod and `@hookform/resolvers` together, then run typecheck and all form/schema contracts.
3. Upgrade React Router in an isolated compatibility change with route, auth-guard, navigation and SPA fallback tests.
4. Upgrade Vite and its SWC plugin together, verify build, dev-server and GitHub Pages output.
5. Resolve PostCSS/esbuild dependency paths with lockfile integrity checks and no unsafe transitive override.
6. Regenerate `package-lock.json` with npm, run `npm ci`, compare dependency tree, and rerun the complete Quality workflow.

Until those coordinated upgrades are complete, record this as an open dependency-security item. The audit report is not a reason to apply a breaking force-upgrade to the active HIMS branch.
