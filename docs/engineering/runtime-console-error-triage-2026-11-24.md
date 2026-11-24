# Runtime console error triage — 24 November 2026

## Scope

Reviewed the supplied browser console captures for the Harmony Health Hub preview at the Lovable project workspace. The application requests shown in the captures target:

`https://pmebpkcufyrbjhawsiyn.supabase.co`

The repository's generated Supabase client defaults to:

`https://ygqoptvezotdqhtimdkr.supabase.co`

The client explicitly allows `VITE_SUPABASE_URL` to override that default. Therefore the browser's observed target is consistent with a preview/build environment variable override; it is not evidence that the source's default URL is wrong.

The connected engineering account can inspect project `ygqoptvezotdqhtimdkr`, but a read-only project lookup for `pmebpkcufyrbjhawsiyn` returned a permission error. No assumptions are made that the two refs are the same project. No SQL, migration, function deployment, or secret change was made.

## Confirmed application-level missing-resource errors

The supplied logs show 404 responses from the preview project for:

- `public.get_my_permissions()`
- `public.get_workflow_notifications(integer)`
- `public.payroll_periods`
- `public.facility_configuration`
- `public.platform_list_facilities()`

The source repository contains the migrations that establish these contracts:

| Runtime resource | Source migration |
|---|---|
| `get_my_permissions()` | `20260918114000_database_permission_catalog.sql` |
| `get_workflow_notifications(integer)` | `20260919064000_scope_it_admin_notifications.sql` |
| `facility_configuration` | `20260912021000_global_hims_operations.sql` and subsequent configuration migrations |
| `platform_list_facilities()` | `20261001200000_platform_superuser_facility_onboarding.sql`, restored by `20261014102730_restore_platform_facility_directory_rpc.sql` |
| `payroll_periods` | `20261008120000_add_hr_payroll_foundation.sql` |

The application client code calls these exact RPC/table names. In particular, the permissions call expects zero arguments and the workflow notifications call passes `_limit`, matching the repository SQL signatures.

## Cross-check against the connected canonical project

Read-only catalog queries against `ygqoptvezotdqhtimdkr` confirmed:

- `get_my_permissions()` exists.
- `get_workflow_notifications(_limit integer)` exists.
- `platform_list_facilities()` and its legacy compatibility alias exist.
- `payroll_periods`, `payroll_items`, `hr_employees`, and `facility_configuration` exist.
- The `admin-create-user` Edge Function is deployed and ACTIVE (version 29).

This is strong evidence that the supplied 404s originate from a different or behind-schema Supabase project selected by the preview runtime, rather than missing definitions in the connected canonical project's live schema. It does not prove that the preview project is safe to repoint or that it is not an intentional development environment.

## Required environment correction

Before any database change, the project owner must verify which Supabase project the Lovable preview is intended to use.

1. Inspect the Lovable preview/deployment environment variable `VITE_SUPABASE_URL` and confirm its project ref.
2. Inspect `VITE_SUPABASE_PUBLISHABLE_KEY` as a matched key for that same project. Never copy a key between Supabase projects.
3. If the intended target is `ygqoptvezotdqhtimdkr`, update the preview's URL and publishable key together in its environment settings, then rebuild/reload the preview.
4. If `pmebpkcufyrbjhawsiyn` is an intentional separate development project, keep it isolated and apply only its own reviewed migrations/functions after obtaining authorized read access and confirming its ledger. Do not point it at production credentials or replay historical migrations blindly.
5. After the target is verified, run a read-only schema preflight for the five resources above, then run the matching forward migrations only if absent and only after environment ledger/provenance checks.

## Edge Function 500

The log shows `admin-create-user` returning HTTP 500, but the browser capture does not include the response body or the Edge Function execution log. The repository function returns structured error messages for failures such as missing administrator role rows, active facility context, profiles, facility memberships, and audit inserts.

The connected canonical project's `admin-create-user` function is ACTIVE. Its logs in the accessible project did not show matching recent events. The browser's request is to the inaccessible `pmeb...` project, so the cause cannot be isolated from the supplied console line alone.

Do not redeploy or change service-role secrets speculatively. Once access to the actual preview project is available, inspect its Edge Function logs for the request timestamp and function slug, then correct the specific failing dependency. Preserve JWT verification and administrator authorization.

## Noise / non-application errors

The following console lines are not evidence of Harmony Health Hub application defects:

- `net::ERR_BLOCKED_BY_CLIENT` for LinkedIn, Google Ads, DoubleClick, and analytics endpoints: browser privacy/ad-blocking extensions commonly block these third-party requests.
- Spotify Pixel “No mapped event found” and RudderStack/Facebook destination timeout messages: analytics destination configuration/availability; not database schema failures.
- `chrome-extension://...` errors and asynchronous message-channel closure: browser extension runtime, not app source.
- React Router v7 future-flag warnings: non-fatal upgrade notices; configure flags only as a deliberate routing compatibility change.
- Lovable editor workspace-flag/profile/payment messages and Lovable API 402: editor account/workspace service responses, not the deployed HIMS backend.
- Resource preload warnings: performance hints; investigate only after verifying which preloaded asset is actually unused.
- `manifest.webmanifest` 401: inspect the manifest request URL and hosting/auth rules separately; the capture does not establish that the manifest is served by the HIMS origin.

## Code behavior observed

- `AuthContext` already falls back to role-default permissions if `get_my_permissions()` is unavailable. This is a compatibility fallback, not a substitute for restoring the intended permission catalog.
- Payroll already surfaces a user-facing error when the payroll-period table is unavailable.
- Notifications currently fail quietly when the workflow notification RPC returns an error; avoid replacing the protected RPC with a direct broad table query, which could bypass role/facility scoping.
- Admin user management already extracts structured Edge Function error responses when available.

## Verification still required

- Obtain authorized access to the exact preview Supabase project ref.
- Confirm its migration ledger, tables, RPC signatures, RLS policies, grants, and Edge Function deployment.
- Capture the `admin-create-user` response body and matching Edge Function logs.
- Verify the manifest's actual origin and response headers.
- Re-test payroll, notifications, permissions, platform facility listing, and user provisioning after correcting the selected environment.

**Safety status:** No production or preview database was modified. No migration was pushed. No Edge Function was redeployed. No secrets were changed.
