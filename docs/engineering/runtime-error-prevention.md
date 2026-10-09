# Runtime Error Prevention and Page Reliability Standard

## Project context

Harmony Health Hub is a React + TypeScript + Vite application using React Router, TanStack Query, Supabase RPCs, facility-scoped authorization, and a GitHub Actions Quality workflow. The repository contains legacy modules with documented schema compatibility shims. Improve these incrementally; do not mass-convert data fetching, enable global strict mode, or remove compatibility shims without reconciling resulting errors and validating clinical/security contracts.

## Phase 1 — Fix the concrete runtime defect

For `WardBedBoard`, the refresh action referenced `loading`, but the component's declared request state is `busy`. The correct repair is to bind the refresh control to `busy`, preserving the existing load flow and avoiding a second, divergent loading state.

When investigating similar `ReferenceError` reports:
1. Trace the deployed bundle symbol back to its source component and inspect every use and declaration.
2. Reuse the component's existing request state if it already represents the same operation.
3. If a state variable is genuinely missing, add it only when its lifecycle and all async paths are understood; otherwise remove obsolete references.
4. Preserve facility boundaries, server-authoritative RPCs, RLS, clinical workflow gates, and existing offline/error handling.
5. Rebuild and verify the actual source revision and deployed asset revision before attributing a fix to a live environment.

## Phase 2 — Prevent undefined identifiers

- Keep TypeScript typecheck and ESLint in the required Quality workflow.
- Do not silence runtime/type errors with new `@ts-nocheck` directives. Existing documented shims should be removed only as their generated database/domain types are reconciled.
- Add focused regression contracts for high-risk modules that have compatibility shims. The Ward & Bed Management contract must assert that the refresh control uses its declared `busy` state and rejects the previous `loading={loading}` regression.
- Tighten TypeScript incrementally by module: resolve compiler errors, remove unnecessary type suppressions, and then enable strict options for that module or project slice. Do not flip global strict settings blindly while legacy modules are still untyped.
- Keep ESLint undefined-name checks effective where compatible with TypeScript; avoid applying core JavaScript rules to TypeScript types in ways that create false positives.

## Phase 3 — Graceful runtime failure

The application already uses a top-level React error boundary. It must continue to:
- render a readable recovery state instead of an unhandled white screen;
- log the error and React component stack for diagnosis;
- provide a safe recovery action; and
- avoid clearing patient data or silently retrying unsafe clinical mutations.

Add route-level boundaries when they can isolate a page without breaking shared authentication, facility context, or navigation. Never treat an error boundary as a substitute for fixing the root cause.

## Phase 4 — Consistent asynchronous data states

TanStack Query is already installed and provided at the application root. Prefer its query/mutation lifecycle for new or refactored server-state workflows where it fits, using stable query keys, cancellation/invalidation, explicit loading/error/empty states, and controlled retries. Do not migrate every existing Supabase loader in one sweep; reconcile each module's realtime subscriptions, facility context, offline behavior, RPC transport, and authorization first. Avoid duplicate state for the same request.

## Phase 5 — Regression coverage and release gate

- Add focused smoke/contract coverage for critical routes, beginning with Ward & Bed Management. Verify the page title, declared loading-state binding, and error-boundary recovery contract.
- Use the repository's existing executable Node regression-contract pattern unless a React-render test framework is already configured and justified; do not add a new test stack solely for a single assertion.
- Keep typecheck, lint, operational/security contracts, and production build required in GitHub Actions. A failed contract must block merge.
- Merge only when required Quality checks are green and GitHub confirms the PR is mergeable. A green static check does not equal browser UAT or confirmation that the deployed bundle has refreshed.
