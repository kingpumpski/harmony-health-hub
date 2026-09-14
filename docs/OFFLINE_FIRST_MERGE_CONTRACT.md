# Offline-First Merge and Continuity Contract

## Purpose

`feature/offline-first-sync` is not a parallel application. It is an operational continuity layer for Harmony Health Hub that must merge cleanly into `main` and continue using the main application's existing authentication, Supabase client, routing, clinical workflows, and UI.

The target operating model is:

1. The facility continues working through temporary connectivity loss after the application has been loaded/cached on the device.
2. Supported mutations are persisted locally before the user is told that the work is safely queued.
3. Connectivity restoration automatically starts synchronization.
4. Synchronization retries until the server accepts the queued work or an explicit authorization/server condition requires operator attention.
5. Existing online workflows remain unchanged when connectivity is healthy.
6. After merge, the main application and offline layer communicate through the existing Supabase client fetch boundary and the `harmony:offline-sync` browser event; no second application shell or duplicate data service is introduced.

## Merge integration points

The following are the required communication points after this branch merges into `main`:

- `src/integrations/supabase/client.ts` continues to construct the single Supabase client and supplies `offlineAwareFetch` as its global fetch implementation.
- The persisted Supabase session remains the authentication source for replay. Queued requests must never depend on a stale manually copied access token.
- `src/components/system/OfflineStatus.tsx` remains mounted from the application shell and acts as the lightweight synchronization coordinator and user-facing connectivity indicator.
- `src/lib/offlineSync.ts` remains the single local outbox/read-model implementation. New offline workflows must extend this boundary rather than creating another queue, provider, or synchronization service.
- `public/sw.js` provides application-shell continuity only. It must not become a second clinical data synchronization engine.
- Explicit server-side offline RPC migrations must be deployed together with the application code that queues them.

## Deployment/merge sequence

Before merging:

1. Apply all offline synchronization migrations to the target Supabase project.
2. Run dependency installation, lint, typecheck, and production build.
3. Exercise the offline browser workflow against a non-production/test environment.
4. Verify that existing online patient, triage, vitals, appointment, authentication, and navigation workflows remain unchanged.

When merged:

1. Deploy the merged application and database migrations as one release boundary.
2. Load the application once while connected so the service worker can establish the application shell/cache.
3. Confirm the persisted authentication session is available.
4. Simulate connectivity loss and perform the supported offline workflows.
5. Restore connectivity and verify the outbox drains automatically without refreshing the page.
6. Verify the same queued records become server-confirmed only after successful replay.
7. Verify a second browser tab does not replay the same outbox concurrently.

## Data continuity rules

- Local queued data is a continuity mechanism, not an authoritative replacement for Supabase.
- Stable identifiers are mandatory for workflows that may be replayed after an interrupted response.
- A queued operation must remain queued after network failure, authentication failure, or server failure rather than being silently discarded.
- Successful synchronization removes the outbox entry only after an HTTP success response.
- Clinical workflows must not be converted to generic offline table writes merely for convenience; each workflow requires an explicit authorization, idempotency, validation, and conflict strategy.
- `Prefer: return=representation` requests remain online-only unless an explicit offline contract can reproduce authoritative server results safely.

## Connectivity recovery

The client retries synchronization:

- immediately when the browser reports that connectivity has returned;
- when the application regains focus or is restored from the browser page lifecycle;
- periodically while the application remains open.

The retry mechanism must remain conservative while offline and must never delete queued work merely because synchronization cannot currently reach the server.

## Expansion rule

Future offline workflows must be added to the same continuity architecture. Do not introduce a second IndexedDB queue, a second synchronization coordinator, or workflow-specific network wrappers that bypass the central Supabase fetch boundary.

High-risk workflows such as prescriptions, medication administration, admissions, laboratory orders, financial transactions, payments, and document uploads require explicit server-side contracts before they are enabled offline.
