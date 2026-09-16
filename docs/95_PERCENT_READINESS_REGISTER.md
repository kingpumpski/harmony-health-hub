# 95% Readiness Register

Updated: 2026-09-16

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
- Post-change performance advisors no longer report the `auth_rls_initplan` warning; the remaining performance advisories are the 195 informational unused-index findings and 21 multiple-permissive-policy findings.
- Authorization helper execute surface was hardened: arbitrary-user helper probes (`has_role`, `is_clinical_staff`, `has_facility_access`, `can_edit_patient_record`) are no longer callable by Data API client roles; current-user helper functions remain available to authenticated clients.

## Current advisor findings that require continued reconciliation

### Performance

- 21 tables have multiple permissive policies for the same authenticated action. These should be consolidated only after verifying that the combined boolean semantics are identical; policy deletion must not be used as a blanket lint-suppression mechanism.
- 195 indexes are currently reported as unused. These are not automatically removable: many cover foreign keys, workflow lookup paths, audit trails, or future operational query patterns. Removal requires workload evidence and duplicate/coverage analysis.

### Security

- The SECURITY DEFINER surface is still being classified function-by-function. Authenticated execution is retained where a function is an intentional server-authoritative workflow with internal authorization checks; internal helper/maintenance functions are being removed from the exposed API surface where appropriate.
- Supabase Auth leaked-password protection is currently disabled. This is an Auth project setting rather than a database migration and must be enabled through the Supabase Auth configuration before final deployment hardening.

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
- Database security contract passes.
- Database schema/migration baseline is reconciled without altering the production migration ledger manually.
- RLS performance advisories are reviewed and material high-volume policies are optimized without changing access semantics.
- Security-definer RPCs have an explicit caller/authorization classification.
- Financial lifecycle invariants are tested end-to-end.
- Clinical order-to-department-queue lifecycle invariants are tested end-to-end.
- Offline replay, backoff, blocked-state and duplicate-replay behavior is tested.
- Browser verification is performed against the deployed build, including console-error review and service-worker activation.
- Vercel deployment succeeds; the current `build-rate-limit` failure is not treated as a successful deployment.

## Known intentional exceptions

- Some authenticated `SECURITY DEFINER` RPCs are intentionally exposed because they are the server-authoritative boundary for clinical workflows. Their presence in the Supabase advisor must be evaluated against the individual function's internal role/facility validation rather than removed indiscriminately.
- Unused-index advisor results are informational during the current low-volume development dataset and must not be interpreted as evidence that every reported index should be dropped.
- The `VM25 startTime` browser-console error previously observed was not attributable to application source and requires clean-profile browser verification before any application change is justified.
