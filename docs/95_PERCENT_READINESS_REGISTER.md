# 95% Readiness Register

Updated: 2026-09-17

## Canonical state

- Repository: `kingpumpski/harmony-health-hub`
- Canonical branch: `main`
- No excluded architecture/offline/careflow branches are part of this readiness register.
- Production Supabase project: `ygqoptvezotdqhtimdkr`

## Completed hardening represented in main/production

- Service-order lifecycle is server-authoritative, including release, override, cancellation, in-progress and completion boundaries.
- Imaging start/complete lifecycle is server-authoritative.
- Laboratory create/collect/result/approval workflow is server-authoritative.
- Pharmacy preparation/dispensing/POS/inventory workflow is server-authoritative.
- Billing payment flow uses row locking/idempotent payment-reference handling and releases associated paid service orders through the authoritative workflow.
- Insurance billing selection is separated from ordinary payment collection; insurance is a claim workflow rather than a cash receipt.
- `/insurance` routes to the dedicated insurance-claims workflow rather than the generic Billing screen.
- Production foreign-key coverage was reconciled: 188 foreign keys have covering indexes and the reconciliation migration is recorded in production as `20260916103212_add_missing_foreign_key_indexes`.
- Service-worker response cloning was corrected and cache version rotation was applied.
- Stale `patients.partner_company` usage was removed from service-order billing queries.
- Internal medication maintenance RPCs remain protected and are no longer invoked by the client UI.
- Telemedicine join/start actions are gated by session lifecycle rather than weakening the server RPC.
- Offline architecture remains deliberately allow-listed and high-risk financial/clinical workflows remain online-only until explicit contracts exist.
- RLS `auth_rls_initplan` remediation was applied to public policies using `auth.uid()`, preserving the policy predicates while wrapping stable auth evaluation in scalar subqueries. A repository migration records the same reconciliation for future environments.
- Post-change performance advisors no longer report the `auth_rls_initplan` warning.
- Authorization helper execute surface was hardened: arbitrary-user helper probes (`has_role`, `is_clinical_staff`, `has_facility_access`, `can_edit_patient_record`) are no longer callable by Data API client roles; current-user helper functions remain available to authenticated clients.
- Trigger-only patient-code generation was removed from the client-callable execute surface.
- Deterministic repository contract checks cover offline idempotency/retry/blocked-state invariants plus service-order, imaging, laboratory, pharmacy and insurance server-authority contracts. The checks run as part of the main Quality workflow before the production build.
- Offline replay now unconditionally removes any persisted `Authorization` header before replay and only applies a fresh bearer token supplied by the active auth provider. A missing fresh token therefore cannot fall back to the historical queued credential.
- Internal audit logging helper `record_system_audit(text,text,text,uuid,text,jsonb)` is no longer executable by `authenticated` or `anon`; the production boundary was verified and the corresponding migration is committed to `main` as `20260916114500_harden_record_system_audit_execute_boundary`.
- The RLS reconciliation pass reduced the previously reported multiple-permissive SELECT findings from 21 to 0 without granting broader access or collapsing semantically distinct policies.
- Cross-platform local development bootstrap is now documented and supported through PowerShell, CMD and Bash scripts; `verify:local` validates the Git root and dependency prerequisites before development starts.
- The database security contract now explicitly covers facility routing administration, facility-scoped report recovery and duplicate-reference idempotency for selected-invoice payments. Production verification confirmed routing/report/payment RPCs are authenticated-only where intended, routing is administrator-gated, report recovery checks facility access, and payment replay detection remains present.

## Current advisor findings that require continued reconciliation

### Performance

- **0 multiple-permissive SELECT findings** remain after the RLS reconciliation pass. The affected policy surfaces were rewritten only where the resulting INSERT/UPDATE/DELETE/SELECT semantics were explicitly preserved.
- **195 unused-index findings remain.** These are informational in the current low-volume dataset and are not being dropped blindly. The foreign-key index reconciliation is already complete; future removals require workload evidence and duplicate/coverage analysis.

### Security

- The current Supabase security advisor reports **84 authenticated-executable SECURITY DEFINER findings** after the audit-helper execute-boundary hardening. The remaining functions are being treated as a function-by-function classification set: intentional server-authoritative clinical/financial/reporting workflows remain callable where their internal authorization contracts are required, while internal-only helpers and maintenance functions are removed from the exposed API surface where appropriate. The latest classification pass verified that `set_facility_routing_mode` is administrator-gated and that `recover_stale_report_run` is facility-scoped; neither was revoked merely to reduce the advisor count.
- Supabase Auth leaked-password protection remains disabled. This is an Auth project setting rather than a database migration and must be enabled through Supabase Auth configuration before final deployment hardening.

### CI / deployment verification

- The latest GitHub `Quality` workflow run for `3118b4614908d67d6dc7aa73301f607130b30624` ended in **`startup_failure` before any job executed**. This is an infrastructure/runner-startup failure, not evidence that TypeScript, lint, contracts or build failed. The quality gates therefore remain unverified until a subsequent run executes them successfully.
- Vercel deployment remains blocked by the previously observed deployment build-rate limit. A successful repository commit or GitHub workflow must not be treated as proof of deployed-browser verification.

## Reconciliation decisions recorded in this pass

- Do not reduce the SECURITY DEFINER advisor count by revoking legitimate clinical/financial workflow RPCs merely to make the advisor green.
- Do not consolidate RLS policies merely because their names appear in the same advisor finding. Their combined boolean semantics must be proven equivalent first.
- Do not remove unused indexes solely because the development dataset has not exercised them.
- Do not convert an `ALL` policy into a different set of policies unless the resulting INSERT/UPDATE/DELETE/SELECT `USING` and `WITH CHECK` semantics are explicitly equivalent.
- The source-level stale-credential replay vulnerability is now hardened: persisted `Authorization` is stripped unconditionally before replay, and only a fresh session token may be attached. A browser-runtime regression test is still required to evidence the behavior in an actual browser; this remains an explicit pre-deployment security gate.
- A GitHub Actions `startup_failure` must not be converted into a code-pass or code-fail claim; execution evidence is required before the corresponding readiness gate is marked complete.
- Facility routing administration and report recovery were retained as authenticated SECURITY DEFINER application boundaries because their internal authorization checks are material to the workflow. The repository database contract now protects those semantics against accidental weakening.
- Selected-invoice payment retry behavior remains explicitly idempotent by payment reference; the repository database contract now guards that invariant.

## Do-not-break rules

1. Do not grant direct table INSERT/UPDATE/DELETE access merely to silence 403 responses.
2. Do not expose internal maintenance RPCs to `authenticated` merely to suppress console errors.
3. Do not turn Insurance into an ordinary payment method.
4. Do not weaken server-side lifecycle validation because a UI action currently fails.
5. Do not use `supabase db push --include-all` against production.
6. Do not manually edit `supabase_migrations.schema_migrations`.
7. Do not fabricate a replacement for the production `canonical_remote_schema` baseline.
8. Do not delete apparently unused indexes without workload/constraint analysis.
9. Do not enable additional offline clinical/financial workflows without explicit authorization, idempotency and conflict contracts.
10. Do not declare production/browser verification complete while Vercel remains blocked by the deployment build-rate limit.

## Final readiness gates

The project should not be declared 95% deployment-ready until these gates are evidenced:

- TypeScript check passes.
- ESLint passes without disabled quality rules.
- Production build passes and emits the required service-worker manifest/assets.
- Operational repository contract checks pass.
- Database security contract passes.
- Database schema/migration baseline is reconciled without altering the production migration ledger manually.
- RLS performance advisories are reviewed and material high-volume policies are optimized without changing access semantics.
- Security-definer RPCs have an explicit caller/authorization classification.
- Financial lifecycle invariants are tested end-to-end.
- Clinical order-to-department-queue lifecycle invariants are tested end-to-end.
- Offline replay, backoff, blocked-state and duplicate-replay behavior is tested, including stale-session credential handling.
- Browser verification is performed against the deployed build, including console-error review and service-worker activation.
- Vercel deployment succeeds; the current `build-rate-limit` failure is not treated as a successful deployment.

## Known intentional exceptions

- Some authenticated `SECURITY DEFINER` RPCs are intentionally exposed because they are the server-authoritative boundary for clinical workflows. Their presence in the Supabase advisor must be evaluated against the individual function's internal role/facility validation rather than removed indiscriminately.
- Unused-index advisor results are informational during the current low-volume development dataset and must not be interpreted as evidence that every reported index should be dropped.
- The `VM25 startTime` browser-console error previously observed was not attributable to application source and requires clean-profile browser verification before any application change is justified.
