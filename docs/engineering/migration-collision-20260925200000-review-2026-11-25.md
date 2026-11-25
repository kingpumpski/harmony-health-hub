# Migration collision review: 20260925200000

Updated: 2026-11-25

## Scope and decision

Reviewed the two candidates sharing version `20260925200000` against the live notification schema, RLS policies, ACLs, indexes and trigger function:

- `20260925200000_notification_advisor_finalization.sql`
- `20260925200000_notification_inbound_email_store.sql`

Both tracks are present in the canonical database and the inspected state matches the main intent of each candidate. The inbound-email table is currently empty and inaccessible to anon/authenticated clients.

**Disposition:** preserve both original files. Do not replay the policy/function replacement blindly; verify migration provenance and exact policy dependencies first. No canonical change is indicated by this read-only comparison.

## A. Notification advisor finalization

The canonical database has both `facility_notification_config` and `facility_notification_provider_connections`, with RLS enabled. Current policies match the candidate's intended access model:

- Configuration SELECT is scoped to facility access.
- Configuration INSERT/UPDATE/DELETE require both facility access and admin/IT-admin role.
- Provider connection SELECT/INSERT/UPDATE/DELETE require facility access and admin/IT-admin role.

The live `prevent_notification_audit_mutation()` function body matches the candidate's immutability behavior and has `search_path = public, pg_temp`. It is a trigger function, not SECURITY DEFINER. It rejects mutations except the explicitly signaled audit-erasure DELETE path.

**Disposition:** the intended policy and trigger-function state is already present. Do not create duplicate policy names or reapply the same policy rewrite without checking all current policy definitions and the exact audit trigger attachment. Add a regression test for facility isolation and provider/config admin-only mutations.

## B. Inbound email storage

The canonical `notification_inbound_emails` table exists and matches the candidate's schema contract:
- provider and provider message ID;
- message ID, sender and recipient arrays;
- subject and text/HTML bodies;
- attachments and raw event JSON;
- received timestamp and processing status;
- nullable facility attribution.

The two candidate indexes are present:
- partial unique `(provider, provider_message_id)` for non-null provider IDs;
- `(facility_id, created_at DESC)`.

RLS is enabled. Explicit deny policies exist for both anon and authenticated on all commands. Authenticated and anon table privileges are absent. The table had zero rows at inspection time and no user-facing triggers. This is consistent with a server-only webhook ingestion surface.

### Additional operational safeguards to verify

The table stores full inbound message content, HTML, attachment metadata and raw provider events. Before enabling ingestion or retention of real messages, verify:
1. The webhook verifies the provider's signature against the raw request body before any database insert.
2. Idempotency uses the provider plus stable provider message ID and handles retries safely.
3. Attachment metadata is treated as untrusted input; file retrieval/scanning and storage access use server-side controls.
4. Facility attribution is derived from trusted routing/configuration, not arbitrary webhook payload fields.
5. Message bodies and raw events have an explicit retention/redaction policy and are not copied into broad notification logs.
6. Any processing queue or worker has a narrow service-role path and records failures/retries without exposing message content to ordinary authenticated clients.

No edge-function implementation or webhook event payload was changed or exercised in this review.

## Required next actions

1. Keep the current notification configuration/provider RLS policies and regression-test facility isolation plus admin/IT-admin write restrictions.
2. Confirm the audit immutability trigger is attached to the intended audit table and test the authorized erasure path with a controlled disposable fixture.
3. Keep inbound email RLS enabled and deny policies for anon/authenticated; do not grant direct Data API access.
4. Review the webhook ingestion function for signature verification, replay protection, idempotency and facility attribution before enabling production inbound email.
5. Define retention and redaction for email body, HTML, attachments and raw provider events.
6. Reconcile original migration provenance and hosted ledger identity before resolving the duplicate version.
7. Validate clean bootstrap and hosted-upgrade paths separately on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No email body, address, attachment, raw event or clinical content was queried; only schema, policies, grants, indexes, function definition and aggregate row count were inspected. No SQL, ACL, policy, trigger, function, edge function or migration ledger entry was changed. The collision remains unresolved.
