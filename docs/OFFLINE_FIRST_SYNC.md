# Offline-first and synchronization

## Purpose

Harmony Health Hub must remain usable when a facility temporarily loses internet connectivity. This branch introduces the first offline-first foundation without replacing the existing Supabase architecture.

## Current architecture

- **Application shell:** `public/sw.js` caches the application entry point and same-origin GET responses so previously visited screens/assets can continue loading while offline.
- **Local persistence:** IndexedDB stores queued Supabase table mutations in `harmony-health-hub-offline`.
- **Mutation interception:** `src/lib/offlineSync.ts` is supplied as the Supabase client's `global.fetch`. `POST`, `PUT`, `PATCH`, and `DELETE` requests to `/rest/v1/` are queued when the browser is offline or a network failure occurs. RPC calls are deliberately excluded until each RPC has an explicit offline contract.
- **Automatic replay:** queued work is replayed in creation order when connectivity returns, when the application starts, and every 30 seconds while the application remains open.
- **Operator visibility:** `OfflineStatus` displays offline state and pending synchronization work.

## Safety boundaries

This is intentionally not a blanket offline database replica. Authentication, AI functions, payments, notifications, and RPC workflows remain online-only unless their workflow is explicitly designed for offline operation. This prevents the client from fabricating clinical, financial, or authorization results while disconnected.

Queued mutations retain their authorization headers from the time they were created. Before production rollout, the sync layer should be extended with an auth-token refresh callback and server-side idempotency keys for every mutation that can safely be retried. This is especially important for high-risk clinical and financial workflows.

## Testing checklist

1. Load the application online at least once and navigate through the screens required for the offline test.
2. Confirm the service worker is active in browser developer tools.
3. Disable network access.
4. Refresh. Previously cached application resources should continue to load.
5. Perform a supported table mutation. The bottom status indicator should report that the change is queued locally.
6. Restore network access. The queue should drain automatically and the pending count should return to zero after successful server responses.
7. Simulate a server error during replay. The failed mutation must remain queued rather than being discarded.
8. Test repeated network loss/recovery to verify that the queue does not lose entries.
9. Test each clinical/financial workflow independently before enabling it for offline use; do not assume that every screen is safe merely because the shell is offline-capable.

## Next hardening stage

- Add authenticated replay with a fresh Supabase session token.
- Add server-side idempotency for retryable writes.
- Add local read models for high-value workflows (registration, triage/vitals, encounters, medication administration, appointments, queue/roster and selected billing operations).
- Add conflict detection using server version/timestamps rather than last-write-wins for clinical records.
- Add an auditable synchronization log and administrator reconciliation screen.
- Add automated browser tests for offline/online transitions and duplicate replay protection.
