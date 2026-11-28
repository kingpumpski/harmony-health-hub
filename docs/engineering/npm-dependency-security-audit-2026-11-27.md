# npm dependency security audit — 2026-11-27

## Observed CI result

The Quality workflow's `npm audit --audit-level=high` inventory reported **10 vulnerabilities: 8 moderate and 2 high** across 478 installed packages. The workflow intentionally marks this step `continue-on-error: true`, so it is an advisory finding and does not block the Quality build.

Advisories visible in the captured audit output include:
- Zod below 4.6.6 — high severity, GHSA-mrhx-c7xc-m3w5.
- esbuild at or below 0.24.2 — moderate, GHSA-67mh-4wv8-2f99; this affects the current Vite/esbuild dependency chain.
- postcss-selector-parser below 6.1.5 — moderate, GHSA-rj75-hqrm-r3gf.
- React Router 6.0.0 through 7.17.0 — moderate advisories GHSA-wrjc-x8rr-h8h6 and GHSA-337j-9hxr-rhxg.

The captured log summarizes two high findings, but exposes only the Zod high advisory in the excerpted report. The second high advisory must be captured from a complete `npm audit --json` output before claiming its package identity.

## Complete audit evidence — 2026-11-28

The Quality workflow now retains the complete `npm audit --json` output as artifact
`npm-audit-report` (run [46125933254](https://github.com/kingpumpski/harmony-health-hub/actions/runs/46125933254),
artifact ID `15255374822`, SHA-256
`1d8f5b3278a044a78ae3fb8c278f2dde040b54f6da2cd110cd0d226f7fa18696`).
The artifact expires 2026-12-12. Its machine-readable summary confirms:

| Package | Severity | Direct dependency | Advisory / affected range |
|---|---|---:|---|
| `vite` | High | Yes | Multiple advisories; affected through `<=6.4.3` |
| `zod` | High | Yes | GHSA-mrhx-c7xc-m3w5; `<4.6.6` |
| `react-router` / `react-router-dom` | Moderate | `react-router-dom` | GHSA-wrjc-x8rr-h8h6 and GHSA-337j-9hxr-rhxg; fixed in 7.18.0+ |
| `esbuild` | Moderate | Transitive | GHSA-67mh-4wv8-2f99; `<=0.24.2` |
| `postcss-selector-parser` | Moderate | Transitive | GHSA-rj75-hqrm-r3gf; `<6.1.5` |
| `drizzle-kit` | Moderate | Yes | Vulnerable dependency chain through `@esbuild-kit/esm-loader` |
| `@esbuild-kit/core-utils`, `@esbuild-kit/esm-loader` | Moderate | Transitive | Inherited from the Drizzle Kit dependency chain |
| `@tailwindcss/typography` | Moderate | Yes | Vulnerable nested selector-parser dependency |

The direct dependency declarations at this branch are Zod `^3.25.76`,
`@hookform/resolvers` `^3.10.0`, React Router DOM `^6.30.6`, Vite
`^5.4.21`, `@vitejs/plugin-react-swc` `^3.11.0`, Drizzle Kit `^0.31.11`,
and Tailwind Typography `^0.5.16`.

The full audit reports 10 package findings (2 high, 8 moderate). Several are
transitive and share a root dependency path; do not count each package row as a
separate independent exploit path. The Vite advisories include development-server
and Windows editor-launcher issues; production deployment exposure depends on
whether the development server/editor tooling is reachable in the deployed
environment. Keep the development server private regardless of the upgrade.

### Repository usage review — 2026-11-28

A targeted source search found the following compatibility constraints:

- Zod is used by `src/lib/mcp/tools/search-patients.ts` and
  `src/lib/mcp/tools/list-appointments.ts`. The Supabase Edge MCP bundle also
  imports `npm:zod@^3.25.76`; changing the frontend npm package does not
  automatically patch this separately resolved Deno dependency.
- React Router v6 is integrated throughout the app shell, role guards, login,
  OAuth consent, patient portal and operational pages. The app uses
  `BrowserRouter`, `Routes`, `Navigate`, `useNavigate`, `useLocation`,
  `useParams`, `useSearchParams` and `Link`. A router major upgrade must
  cover these routes and the existing GitHub Pages fallback contract.
- Vite configuration contains custom production plugins for compressed assets
  and GitHub Pages SPA fallback, alongside the SWC plugin and Lovable MCP
  plugin. Upgrade tests must verify generated `dist/index.html`,
  `dist/404.html`, compressed assets and deep-link recovery.
- Drizzle Kit is declared as a dev dependency and referenced by
  `drizzle.config.ts`; however, `drizzle/schema.ts` is intentionally blank and
  no package script invokes Drizzle Kit. The two Drizzle migration files are
  still present. Treat removal or replacement as a separately reviewed
  developer-tooling decision, not an automatic security fix.

This source review strengthens the case against a blanket force-upgrade. It
also identifies the independent Edge MCP Zod dependency as a separate patch
target to review and test before release.

## Remediation sequencing

1. **Zod:** migrate validation schemas and resolver integration to a patched Zod
   release in a dedicated change. Zod 4 is a major upgrade; verify schema APIs,
   inferred TypeScript types, coercion/default behavior, and form error mapping.
2. **Vite/esbuild:** evaluate the latest patched compatible Vite line and matching
   SWC plugin peer range first. Do not assume the audit's suggested Vite 8
   automatic fix is the only route; validate supported upgrade paths, build
   output, dev server, and GitHub Pages SPA artifacts.
3. **React Router:** keep v6 routing stable until a separately tested v7 migration
   covers route loaders/actions, nested layouts, auth guards, navigation and
   GitHub Pages deep links. Verify whether a patched supported v6 release exists
   before taking a major upgrade.
4. **Drizzle Kit:** inspect whether the project uses Drizzle Kit at runtime or
   only for development/schema tooling. Replace or remove obsolete
   `@esbuild-kit` transitive paths through a supported Drizzle Kit release,
   after validating config and generated SQL workflows.
5. **Tailwind Typography/PostCSS:** verify a patched dependency path without
   blindly downgrading the typography plugin; run CSS build and visual contracts.
6. Regenerate the lockfile only after selected versions are proven compatible,
   then run `npm ci`, typecheck, lint, build and the complete contract suite.

No dependency versions or lockfile entries were changed by this audit follow-up.
The audit remains a release-blocking security task until both high findings are
remediated and a fresh audit reports no high/critical vulnerabilities.

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
