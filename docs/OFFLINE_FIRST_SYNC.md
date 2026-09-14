# Offline-first and synchronization

## Purpose

Harmony Health Hub must remain usable when a facility temporarily loses internet connectivity. This branch introduces an offline-first foundation without replacing the existing Supabase architecture.

## Current architecture

- **Application shell:** `public/sw.js` caches the application entry point and same-origin GET responses so previously visited screens/assets can continue loading while offline. Navigation falls back to the cached `index.html`; non-navigation assets are never replaced with HTML responses.
- **Local persistence:** IndexedDB stores queued Supabase table mutations, synchronization history, and explicit local continuity/read models in `harmony-health-hub-offline`.
- **Mutation interception:** `src/lib/offlineSync.ts` handles eligible PostgREST table writes plus explicitly contracted appointment and vital-sign RPC workflows. Other RPC calls remain excluded.
- **Representation safety:** requests using `Prefer: return=representation` are not queued because those callers require authoritative server-generated data.
- **Automatic replay:** queued work is replayed in creation order when connectivity returns, at application startup, and periodically while the application remains open.
- **Fresh authentication:** replay obtains the active Supabase access token before each queued request.
- **Retry identity:** each queued mutation receives a stable `X-Harmony-Idempotency-Key`. The generic queue does not claim that this header alone provides server-side duplicate protection.
- **Cross-tab coordination:** a short-lived local-storage lock prevents common concurrent replay races.
- **Synchronization audit:** queue, success, and failure events are persisted in IndexedDB.
- **Operator visibility:** `OfflineStatus` displays offline state and pending synchronization work; the admin-only `/admin/offline-sync` screen provides a local-device reconciliation view without exposing queued mutation payload bodies.

## Explicit offline workflows

### Patient registration

Patient registration has an explicit offline command with a stable client-generated patient UUID and patient code. The queued PostgREST command uses the patient's primary key as its conflict target and `resolution=ignore-duplicates`, so a replay after a successfully committed request with a lost response does not create a second patient. The UI distinguishes locally queued registration from server-confirmed registration. Patient documents/photos remain online-only until Storage synchronization is explicitly designed.

### Triage assessment

Triage has an explicit offline command using the existing `triage_assessments` schema. The assessment receives a stable client-generated UUID and is queued with `return=minimal`, `on_conflict=id`, and `resolution=ignore-duplicates`; a replay after a lost response therefore becomes a server-side no-op for the same assessment ID. The UI explicitly states that an offline assessment is not yet server-confirmed. Server-side validation and RLS remain authoritative when synchronization occurs.

### Vital signs

Vital signs have an explicit offline contract without opening direct client writes to `vital_signs`. When the existing `record_patient_vitals` workflow is invoked while disconnected, the fetch boundary converts that specific command into `record_patient_vitals_offline` and attaches a stable UUID. The server-side `SECURITY DEFINER` function re-checks the clinical role, inserts using the supplied UUID, calculates BMI when height and weight are available, and returns an existing-record result if the UUID has already been committed. This makes an interrupted response safe to replay without creating a second vital-sign record.

### Appointment scheduling

Appointment scheduling has an explicit offline contract because it is an operational workflow with a server-authoritative role check. The existing `create_patient_appointment` command is converted only while offline into `create_patient_appointment_offline`, with a stable UUID. The server-side function checks the allowed roles, inserts the supplied UUID, and returns an existing-record result when a replay encounters an appointment already committed with the same UUID. This prevents duplicate appointments caused by an interrupted synchronization response.

## Local continuity/read models

Patient registration, triage, selected vital signs and appointment scheduling write explicit local read models alongside their queued mutation. These records are intentionally scoped to workflows that already have stable identifiers and explicit offline contracts.

- Records are marked **Queued locally** immediately after local persistence.
- A record changes to **Server confirmed** only after its associated queued mutation receives a successful HTTP response during synchronization.
- The admin Offline Synchronization Center displays these continuity records without displaying raw queued clinical payloads.
- Local continuity is not a substitute for the authoritative Supabase record and is not treated as server confirmation.
- The IndexedDB schema is version 4; existing queued mutations and synchronization history are retained during upgrade.

This does **not** make every clinical workflow offline. Emergency actions, medication administration, prescriptions, financial operations, admissions, laboratory orders and other high-risk operations remain online-only until they receive an explicit workflow contract, server-side idempotency, and conflict handling.

## Safety boundaries

This is intentionally not a blanket offline database replica. Authentication, AI functions, notifications, payments and uncontracted RPC workflows remain online-only unless their workflow is explicitly designed for offline operation. This prevents the client from fabricating clinical, financial, or authorization results while disconnected.

A queued mutation receives an HTTP 202 response with explicit offline metadata. Workflows that depend on an authoritative returned row are intentionally not queued.

The generic `X-Harmony-Idempotency-Key` remains a client-side retry identity until a server workflow explicitly consumes it. Patient registration and triage currently achieve retry safety through stable primary keys plus PostgREST duplicate-ignore semantics. Vital signs and appointments achieve retry safety through explicit server RPC contracts and stable UUIDs. These are deliberately workflow-specific contracts rather than a universal database idempotency layer.

## Testing checklist

1. Load the application online at least once and navigate through screens required for offline testing.
2. Confirm the service worker is active.
3. Sign in while online and keep the session persisted.
4. Disable network access.
5. Refresh and verify cached application resources continue to load.
6. Verify patient registration can be saved locally and later synchronized.
7. Verify triage can be captured locally and later synchronized with its stable UUID.
8. Verify vital signs can be captured through the existing Patient Hub vital-sign workflow while disconnected and appear as queued locally.
9. Verify appointment scheduling can be captured through the existing Patient Hub appointment workflow while disconnected and appear as queued locally.
10. Restore connectivity and verify patient, triage, vital-sign and appointment queues drain.
11. Verify offline continuity records change to server-confirmed only after successful replay.
12. Verify mutations requiring `return=representation` are not falsely queued.
13. Simulate a server error during replay and verify the failed item remains queued with synchronization history.
14. Open two tabs and verify only one performs queue replay at a time.
15. Verify document/photo uploads remain online-only during offline registration.
16. Repeat synchronization after a deliberately interrupted response and verify patient/triage/vital-sign/appointment retry behavior is idempotent.
17. Open `/admin/offline-sync` as an administrator and verify pending mutations, continuity records, failure history, connectivity state and manual synchronization are visible without displaying queued mutation payload bodies.
18. Test duplicate/retry behavior for every additional clinical and financial workflow before enabling it offline.

## Production hardening still required

- Extend server-side retry/idempotency contracts to additional explicit workflows rather than treating the generic header as sufficient.
- Add conflict detection using server versions/timestamps rather than last-write-wins for clinical records.
- Replace the local synchronization history view with durable server-side synchronization/reconciliation events when multi-device facility-wide reconciliation is required.
- Add automated browser tests for offline/online transitions, authentication refresh, concurrent-tab locking, representation safety, and duplicate replay protection.
- Expand service-worker precaching to production hashed JS/CSS assets if full cold-start offline navigation is required.
- Add Storage-aware offline document synchronization only if the facility requires it and after defining encryption, retention, authorization, and conflict behavior.
- Extend local read models to additional workflows only after inspecting their schemas, authorization model, mutation path, and conflict/idempotency requirements.
