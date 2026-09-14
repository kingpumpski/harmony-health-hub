# Offline-first and synchronization

## Purpose

Harmony Health Hub must remain usable when a facility temporarily loses internet connectivity. This branch introduces an offline-first foundation without replacing the existing Supabase architecture.

## Current architecture

- **Application shell:** `public/sw.js` caches the application entry point and same-origin GET responses so previously visited screens/assets can continue loading while offline. Navigation falls back to the cached `index.html`; non-navigation assets are never replaced with HTML responses.
- **Local persistence:** IndexedDB stores queued Supabase table mutations in `harmony-health-hub-offline`.
- **Mutation interception:** `src/lib/offlineSync.ts` is supplied as the Supabase client's `global.fetch`. `POST`, `PUT`, `PATCH`, and `DELETE` requests to `/rest/v1/` are queued when the browser is offline or a network failure occurs. RPC calls are deliberately excluded until each RPC has an explicit offline contract.
- **Automatic replay:** queued work is replayed in creation order when connectivity returns, when the application starts, and every 30 seconds while the application remains open.
- **Fresh authentication:** replay asks the active Supabase client for the current access token before each queued request, so an expired token captured while offline is not blindly reused.
- **Retry identity:** each queued mutation receives a stable `X-Harmony-Idempotency-Key` that is preserved across retries. The header is ready for server-side idempotency enforcement; the client does not claim duplicate protection until the server/workflow honors the key.
- **Cross-tab coordination:** a short-lived local-storage lock prevents multiple open tabs from replaying the same queue concurrently. The lock expires automatically to avoid permanent deadlocks after a crashed tab.
- **Operator visibility:** `OfflineStatus` displays offline state and pending synchronization work.

## Safety boundaries

This is intentionally not a blanket offline database replica. Authentication, AI functions, payments, notifications, and RPC workflows remain online-only unless their workflow is explicitly designed for offline operation. This prevents the client from fabricating clinical, financial, or authorization results while disconnected.

A queued mutation receives an HTTP 202 response with an empty JSON collection and explicit `X-Harmony-Offline-Queued` metadata. Existing workflows that depend on a server-generated returned row, generated identifiers, calculated totals, or other representation data must be tested and, where necessary, converted to an explicit offline command/local-read-model pattern rather than assuming the queued response is equivalent to a successful server response.

The stable idempotency key alone is not a server-side guarantee. Until database/workflow-specific idempotency handling is implemented, replay of a request whose server response was lost can still theoretically duplicate the underlying write. High-risk clinical and financial operations must therefore remain online-only or receive explicit server-side idempotency before production offline use.

## Testing checklist

1. Load the application online at least once and navigate through the screens required for the offline test.
2. Confirm the service worker is active in browser developer tools.
3. Disable network access.
4. Refresh. Previously cached application resources should continue to load.
5. Perform a supported table mutation. The bottom status indicator should report that the change is queued locally.
6. Restore network access. The queue should drain automatically and the pending count should return to zero after successful server responses.
7. Verify a replayed mutation uses the current Supabase access token rather than a stale token captured before the outage.
8. Simulate a server error during replay. The failed mutation must remain queued rather than being discarded.
9. Open two application tabs and restore connectivity. Only one tab should own queue replay at a time.
10. Test repeated network loss/recovery to verify that the queue does not lose entries.
11. Test each clinical/financial workflow independently before enabling it for offline use; do not assume that every screen is safe merely because the shell is offline-capable.

## Production hardening still required

- Implement database/workflow-specific server-side idempotency for retryable writes, using the stable `X-Harmony-Idempotency-Key`.
- Add local read models for high-value workflows (registration, triage/vitals, encounters, medication administration, appointments, queue/roster and selected billing operations).
- Add conflict detection using server version/timestamps rather than last-write-wins for clinical records.
- Add an auditable synchronization log and administrator reconciliation screen.
- Add automated browser tests for offline/online transitions, authentication refresh, concurrent-tab locking, and duplicate replay protection.
- Expand service-worker precaching to the production build's hashed JS/CSS assets if full cold-start offline navigation is required. The current runtime cache only guarantees assets that have already been fetched online.
