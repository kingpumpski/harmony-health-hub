# Offline-first and synchronization

## Purpose

Harmony Health Hub must remain usable when a facility temporarily loses internet connectivity. This branch introduces an offline-first foundation without replacing the existing Supabase architecture.

## Current architecture

- **Application shell:** `public/sw.js` caches the application entry point and same-origin GET responses so previously visited screens/assets can continue loading while offline. Navigation falls back to the cached `index.html`; non-navigation assets are never replaced with HTML responses.
- **Local persistence:** IndexedDB stores queued Supabase table mutations in `harmony-health-hub-offline` and keeps durable synchronization history.
- **Mutation interception:** `src/lib/offlineSync.ts` handles eligible PostgREST table writes. RPC calls are excluded until each RPC has an explicit offline contract.
- **Representation safety:** requests using `Prefer: return=representation` are not queued because those callers require authoritative server-generated data.
- **Automatic replay:** queued work is replayed in creation order when connectivity returns, at application startup, and periodically while the application remains open.
- **Fresh authentication:** replay obtains the active Supabase access token before each queued request.
- **Retry identity:** each queued mutation receives a stable `X-Harmony-Idempotency-Key`. The client does not claim duplicate protection until the server/workflow honors that key.
- **Cross-tab coordination:** a short-lived local-storage lock prevents common concurrent replay races.
- **Synchronization audit:** queue, success, and failure events are persisted in IndexedDB.
- **Operator visibility:** `OfflineStatus` displays offline state and pending synchronization work.

## Explicit offline workflows

### Patient registration

Patient registration has an explicit offline command with a stable client-generated patient UUID and patient code. The UI distinguishes locally queued registration from server-confirmed registration. Patient documents/photos remain online-only until Storage synchronization is explicitly designed.

### Triage assessment

Triage now has an explicit offline command using the existing `triage_assessments` schema. The assessment receives a stable client-generated UUID and is queued with `return=minimal`; the UI explicitly states that an offline assessment is not yet server-confirmed. The selected clinical priority and measured values are persisted with the queued assessment. Server-side validation remains authoritative when synchronization occurs.

This does **not** make every clinical workflow offline. Emergency actions, RPC workflows, medication administration, financial operations and other high-risk operations remain online-only until they receive an explicit workflow contract, server-side idempotency, and conflict handling.

## Safety boundaries

This is intentionally not a blanket offline database replica. Authentication, AI functions, notifications, payments and RPC workflows remain online-only unless their workflow is explicitly designed for offline operation. This prevents the client from fabricating clinical, financial, or authorization results while disconnected.

A queued mutation receives an HTTP 202 response with explicit offline metadata. Workflows that depend on an authoritative returned row are intentionally not queued.

The stable idempotency key alone is not a server-side guarantee. Until database/workflow-specific idempotency handling is implemented, replay of a request whose server response was lost can theoretically duplicate the underlying write. High-risk clinical and financial operations must therefore remain online-only or receive explicit server-side idempotency before production offline use.

## Testing checklist

1. Load the application online at least once and navigate through screens required for offline testing.
2. Confirm the service worker is active.
3. Sign in while online and keep the session persisted.
4. Disable network access.
5. Refresh and verify cached application resources continue to load.
6. Verify patient registration can be saved locally and later synchronized.
7. Verify triage can be captured locally and later synchronized with its stable UUID.
8. Verify offline registration/triage screens distinguish queued records from server-confirmed records.
9. Verify mutations requiring `return=representation` are not falsely queued.
10. Restore connectivity and verify eligible queues drain.
11. Simulate a server error during replay and verify the failed item remains queued with synchronization history.
12. Open two tabs and verify only one performs queue replay at a time.
13. Verify document/photo uploads remain online-only during offline registration.
14. Test duplicate/retry behavior for every clinical and financial workflow before enabling it offline.

## Production hardening still required

- Implement database/workflow-specific server-side idempotency for retryable writes using `X-Harmony-Idempotency-Key`.
- Add local read models for registration, triage/vitals, encounters, medication administration, appointments, queue/roster and selected billing operations where clinically safe.
- Add conflict detection using server versions/timestamps rather than last-write-wins for clinical records.
- Add an auditable administrator synchronization/reconciliation screen backed by durable server-side events.
- Add automated browser tests for offline/online transitions, authentication refresh, concurrent-tab locking, representation safety, and duplicate replay protection.
- Expand service-worker precaching to production hashed JS/CSS assets if full cold-start offline navigation is required.
- Add Storage-aware offline document synchronization only if the facility requires it and after defining encryption, retention, authorization, and conflict behavior.
